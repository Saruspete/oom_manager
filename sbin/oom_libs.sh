#!/bin/ksh


LOG_TO_OUT="${LOG_TO_OUT:-0}"
LOG_TO_DBG="${LOG_TO_DBG:-0}"
LOG_TO_FILE="${LOG_TO_FILE:-1}"
LOG_FILE="${LOG_FILE:-/var/log/oom_manager.log}"


BIN_PS=/bin/ps
BIN_AWK=/usr/bin/awk
BIN_SED=/bin/sed
BIN_CAT=/bin/cat
BIN_SU=/bin/su


function oom_logdate {
	date "+%y-%m-%d_%H:%M:%S"
}

function oom_logerr {
	DATE="$(oom_logdate)"
	[ "$LOG_TO_OUT" = "1" ]  && { echo "[$DATE] [ERR] $@" ; }
	[ "$LOG_TO_FILE" = "1" ] && { echo "[$DATE] [ERR] $@" >> $LOG_FILE ; }
}

function oom_logdbg {
	[ "$LOG_TO_DBG" = "0" ] && return 0;

	DATE="$(oom_logdate)"
	[ "$LOG_TO_OUT" = "1" ]  && { echo "[$DATE] [DBG] $@" >&2 ; }
	[ "$LOG_TO_FILE" = "1" ] && { echo "[$DATE] [DBG] $@" >> $LOG_FILE ; }

}

function oom_log {
	DATE="$(oom_logdate)"
	[ "$LOG_TO_OUT" = "1" ]  && { echo "[$DATE] [STD] $@" ; }
	[ "$LOG_TO_FILE" = "1" ] && { echo "[$DATE] [STD] $@" >> $LOG_FILE ; }
}


function oom_setadj {
	
	oom_logdbg "[oom_setadj] Calling oom_setadj with \"$1\" and \"$2\""

	[ -z "$1" ] && { 
		oom_logerr "[oom_setadj] Wrong PID arg given \"$1\""
		return 1
	}
	[ -z "$2" -o "$2" -lt -15 -o "$2" -gt 17 ] && {
		oom_logerr "[oom_setadj] Wrong Score given \"$2\""
	}
	
	PID=$1
	SCORE=$2
	[ -e "/proc/$PID/" ] || {
		oom_logerr "[oom_setadj] Path does not exists /proc/$PID/"
		return 1
	}
	
	OSCORE="$($BIN_CAT /proc/$PID/oom_adj)"
	
	# Set the score
	oom_logdbg "[oom_setadj] Setting adj of $PID to $SCORE"
	echo "$SCORE" > /proc/$PID/oom_adj

	# Check if scoring was successfull
	NSCORE="$($BIN_CAT /proc/$PID/oom_adj 2>/dev/null)"
	oom_logdbg "[oom_setadj] New adj of $PID is $NSCORE"
	
	# Good ? okay nice
	[ -n "$NSCORE" ] && {
		[ "$NSCORE" -eq "$SCORE" ] && {
			oom_log "[oom_setadj] $PID set from $OSCORE to $NSCORE"
			return 0
		} || {
			# SHITSHITSHITSHITSHIT
			oom_logerr "[oom_setadj] $PID adj is $NSCORE was $OSCORE but should be $SCORE"
			return 1
		}
	} || {
		# Empty score ? Process was killed. Don't bother me
		oom_logdbg "[oom_setadj] $PID got an empty new score. Maybe killed in the meantime ?"
		return 0
	}


}

function oom_getadj {	
	[ -z "$1" ] && { 
		oom_logerr "[oom_getadj] Wrong PID arg given \"$1\""
		return 1
	}
	PID=$1
	
	$BIN_CAT /proc/$PID/oom_adj
	return $?
}

function oom_start {
	oom_log "[main] Launching manual OOM Killer" 	
	echo "f" > /proc/sysrq-trigger
	
}

function oom_getprocess {
	
	$BIN_PS -ewww -o pid,ppid,user,uid,ruid,gid,rgid,args | # Get the fields
	$BIN_SED -e 's/  */ /g' -e 's/^ *//' |					# Rewrite output
	$BIN_AWK '($1 != PROCINFO["ppid"] && $2 != PROCINFO["ppid"]) { print }'	# remove myself
#	$BIN_AWK '{print substr($0, index($1,$7)) }'
	
}

