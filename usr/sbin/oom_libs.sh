# Shell library

typeset -i LOG_TO_OUT="${LOG_TO_OUT:-0}"
typeset -i LOG_TO_DBG="${LOG_TO_DBG:-0}"
typeset -i LOG_TO_FILE="${LOG_TO_FILE:-1}"
typeset -i LOG_TO_SYS="${LOG_TO_SYS:-0}"

typeset    LOG_FILE="${LOG_FILE:-/var/log/oom_manager.log}"
typeset    LOG_SYS_FACILITY="kern"
typeset    LOG_SYS_TAG="oom_manager"

typeset    BIN_PS=/bin/ps
typeset    BIN_AWK=/usr/bin/awk
typeset    BIN_SED=/bin/sed
typeset    BIN_CAT=/bin/cat
typeset    BIN_SU=/bin/su
typeset    BIN_IPCS=/usr/bin/ipcs
typeset    BIN_LOGGER=/usr/bin/logger


# Pre-check for bins
$BIN_AWK --version | while read line; do
	[[ $line != GNU\ Awk* ]] && {
		echo "Expecting GNU Awk. Stopping" >&2
		exit 1
	}
	break;
done

function oom_logdate {
	date "+%y-%m-%d_%H:%M:%S"
}

function oom_logerr {
	typeset DATE="$(oom_logdate)"
	[[ "$LOG_TO_OUT" = "1" ]]  && { echo "[$DATE] [ERR] $@" ; }
	[[ "$LOG_TO_FILE" = "1" ]] && { echo "[$DATE] [ERR] $@" >> $LOG_FILE ; }
	[[ "$LOG_TO_SYS" = "1" ]]  && { $BIN_LOGGER -p "${LOG_SYS_FACILITY}.err" -t "${LOG_SYS_TAG}" "$@" ; }
}

function oom_logdbg {
	[[ "$LOG_TO_DBG" = "0" ]] && return 0;

	typeset DATE="$(oom_logdate)"
	[[ "$LOG_TO_OUT" = "1" ]]  && { echo "[$DATE] [DBG] $@" >&2 ; }
	[[ "$LOG_TO_FILE" = "1" ]] && { echo "[$DATE] [DBG] $@" >> $LOG_FILE ; }
	[[ "$LOG_TO_SYS" = "1" ]]  && { $BIN_LOGGER -p "${LOG_SYS_FACILITY}.debug" -t "${LOG_SYS_TAG}" "$@" ; }

}

function oom_log {
	typeset DATE="$(oom_logdate)"
	[[ "$LOG_TO_OUT" = "1" ]]  && { echo "[$DATE] [STD] $@" ; }
	[[ "$LOG_TO_FILE" = "1" ]] && { echo "[$DATE] [STD] $@" >> $LOG_FILE ; }
	[[ "$LOG_TO_SYS" = "1" ]]  && { $BIN_LOGGER -p "${LOG_SYS_FACILITY}.info" -t "${LOG_SYS_TAG}" "$@" ; }
}


function oom_transformunit {

	if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
		oom_logerr "[oom_transformunit] Calling with wrong number of ags : \"$@\""
		return 1
	fi

	typeset    STR=$1
	typeset    VAL=$2
	typeset -i AWKRET
	echo $STR | $BIN_AWK -v REF=$VAL 'BEGIN { IGNORECASE=1; coef=1 }
	{
		if (match($1, /^[0-9]+[bkmg%]?$/)) {
			ind = match($1, /[bBkKmMgG%]/);
			if (ind > 0) {
				unit=substr($1, ind, 1);
				val=substr($1, 0, ind);
			} else {
				unit="";
				val=$1
			}
# Nice, switch isnt enabled on gawk RHEL... Very nice dudes !
#			switch (unit) {
#				case "g":   coef*=1024
#				case "m":   coef*=1024
#				case "k":   coef*=1
#							break;
#				case "b":
#				default:	coef/=1024;
#							break;
#				case "%":
#					if (!REF) {	exit(253); }
#					coef=1
#					val = REF/100*val
#			}
			if (unit == "b" || unit == "") { coef = 1/1024; }
			if (unit == "k") { coef = 1; }
			if (unit == "m") { coef = 1024; }
			if (unit == "g") { coef = 1048576; }
			if (unit == "%") {
				if (!REF) { exit(253); }
				coef = 1;
				val = REF/100*val;
			}
			print int(val*coef)
		}
	}'
	AWKRET=$?

	[[ $AWKRET -eq 253 ]] && {
		oom_logerr "[oom_transformunit] Calling a percent value \"$STR\" without ref value"
		return 1
	}
	[[ $AWKRET -ne 0 ]] && {
		oom_logerr "[oom_transformunit] error in AWK, code $AWKRET..."
		return 1
	}

	return 0
}




function oom_setadj {

	oom_logdbg "[oom_setadj] Calling oom_setadj with \"$1\" and \"$2\""

	[[ -z "$1" ]] && {
		oom_logerr "[oom_setadj] Wrong PID arg given \"$1\""
		return 1
	}
	if [[ -z "$2" ]] || [[ "$2" -lt -15 ]] || [[ "$2" -gt 17 ]]; then
		oom_logerr "[oom_setadj] Wrong Score given \"$2\""
	fi

	typeset -i PID=$1
	typeset -i SCORE=$2
	[[ -e "/proc/$PID/" ]] || {
		oom_logerr "[oom_setadj] Path does not exists /proc/$PID/"
		return 1
	}

	typeset OSCORE="$($BIN_CAT /proc/$PID/oom_adj)"

	# Set the score
	oom_logdbg "[oom_setadj] Setting adj of $PID to $SCORE"
	echo "$SCORE" > /proc/$PID/oom_adj

	# Check if scoring was successfull
	NSCORE="$($BIN_CAT /proc/$PID/oom_adj 2>/dev/null)"
	oom_logdbg "[oom_setadj] New adj of $PID is $NSCORE"

	# Good ? okay nice
	if [[ -n "$NSCORE" ]]; then
		if [[ "$NSCORE" -eq "$SCORE" ]]; then
			oom_log "[oom_setadj] $PID set from $OSCORE to $NSCORE"
			return 0
		else
			# SHITSHITSHITSHITSHIT
			oom_logerr "[oom_setadj] $PID adj is $NSCORE was $OSCORE but should be $SCORE"
			return 1
		fi
	else
		# Empty score ? Process was killed. Don't bother me
		oom_logdbg "[oom_setadj] $PID got an empty new score. Maybe killed in the meantime ?"
		return 0
	fi


}

function oom_getadj {
	[[ -z "$1" ]] && {
		oom_logerr "[oom_getadj] Wrong PID arg given \"$1\""
		return 1
	}
	typeset -i PID=$1

	$BIN_CAT /proc/$PID/oom_adj 2>/dev/null
	return $?
}

function oom_trigger {
	oom_log "[oom_trigger] Launching manual OOM Killer"
	echo "f" > /proc/sysrq-trigger

}

function oom_getprocess {

	$BIN_PS -ewww -o pid,ppid,user,uid,ruid,gid,rgid,args | # Get the fields
	$BIN_SED -e 's/  */ /g' -e 's/^ *//' |					# Rewrite output
	$BIN_AWK '($1 != PROCINFO["ppid"] && $2 != PROCINFO["ppid"]) { print }'	# remove myself
#	$BIN_AWK '{print substr($0, index($1,$7)) }'

}

function oom_getmemorytotal {
	$BIN_AWK 'BEGIN{ ORS=" "} /^(MemTotal|SwapTotal):/{print $2} END { print "\n" }' /proc/meminfo
}

function oom_getmemoryusage {

	# Get the SHM
	typeset -i SHM=$($BIN_IPCS -m| $BIN_AWK 'BEGIN{total=0} /^0x/ { total+=$5} END { print int(total/1024)}')
	oom_logdbg "[oom_getmemoryusage] Found $SHM KB of SHM"

	# Here the deal :
	# If we are in HugePages, the SHM is pre-allocated by kernel and is "anon"
	# If we are not, the SHM is allocated on the fly and is in "cache"

	# Find the total real free memory
	typeset TOTAL=$($BIN_AWK -v shm=$SHM 'BEGIN{free=0; cache=0; huge=1; swap=0; ORS=" "}
		/^MemFree:/{free=$2}
		/^(Cached|Buffers):/ {cache+=$2}
		/^(HugePages_Total|Hugepagesize):/ {huge *= $2}
		/^(SwapFree):/ { swap=$2 }
		END {
			if (huge > 1) {
				print (free+cache-huge)
			} else {
				print (free+cache-shm)
			}
			print swap
		}' /proc/meminfo)

	oom_logdbg "[oom_getmemoryusage] Found $TOTAL free mem/swp KB"

	echo $TOTAL
	return 0
}
