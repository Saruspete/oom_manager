#!/bin/ksh

# #############################################################################
# OOM Killer score manager - Javamine
# Created to adjust Linux OOM_Killer scores
# Adrien Mahieux <adrien.mahieux-ext@socgen.com>
# #############################################################################
# 
# This file is the main loop. The score is set from results returned by the
# "PATH_SCORING" script.
# 
# #############################################################################


OOM_VERSION="0.3"
OOM_SCRIPT="$0"

. $(dirname $0)/oom_libs.sh


function oom_usage {
	oom_getmemoryusage | ( read FREEMEM FREESWP
	FREEMEMTRG="N/A"
	FREESWPTRG="N/A"
	[ $EXEC_PREOOMMEMVAL -gt 0 ] && {
		[ $FREEMEM -lt $EXEC_PREOOMMEMVAL ] && {
			FREEMEMTRG="TRIGGER !" 
		} || {
			FREEMEMTRG="OK, $(($FREEMEM - $EXEC_PREOOMMEMVAL)) free"
		}
	}

	[ $EXEC_PREOOMSWPVAL -gt 0 ] && {
		[ $FREESWP -lt $EXEC_PREOOMSWPVAL ] && {
			FREESWPTRG="TRIGGER !" 
		} || {
			FREESWPTRG="OK, $(($FREESWP - $EXEC_PREOOMSWPVAL)) free"
		}
	}


	echo "Linux OOM-Killer Manager v$OOM_VERSION"
	echo "Fix OOM_Scores of selected processes"
	echo 
	echo "Usage : $OOM_SCRIPT [OPTS]"
	echo 
	echo "Options:"
	echo " -s =  Seconds to sleep between process check (current: $LOOP_SLEEP) "
	echo " -c =  Max number of loops. -1 for infinite (current: $LOOP_MAX)"
	echo " -d    Daemon mode (equivalent to \"-c -1\")"
	echo
	echo "Logging:"
	echo " -v    Increase the verbosity level (current: $EXEC_VERB)"
	echo " -l =  Log to file (current: $PATH_LOGFILE)"
	echo " -L =  Log to syslog (current: $LOG_TO_SYS Facility : $LOG_SYS_FACILITY)"
	echo 
	echo "Scoring:"
	echo " -S =  Program to execute for getting the scores (current: $PATH_SCORING)"
	echo " -p =  Add a path for profiles (current: $PATH_PROFILES)"
	echo 
	echo " -t    Trigger the OOM Killer feature (data displayed in /var/log/messages)"
	echo
	echo "Pre-oom triggering. "
	echo "You can use a unit of K,M,G,T,%"
	echo " -f =  Free RAM needed  (current: $FREEMEM  min: $EXEC_PREOOMMEMVAL  status: $FREEMEMTRG)"
	echo " -F =  Free SWAP needed (current: $FREESWP  min: $EXEC_PREOOMSWPVAL  status: $FREESWPTRG)"
	echo 
	echo "Help:"
	echo " -h   Display this help and used values"
	echo
	)
}


# Opts management

# Int vars
typeset -i LOOP_SLEEP=60		# In-loop sleep time
typeset -i LOOP_MAX=1			# Max count of loops
typeset -i LOOP_COUNT=0			# Current count of loops
typeset -i LOOP_DAEMON=0		# Should we daemonize 
typeset -i EXEC_OOM=0			# Should we manually test-trigger the oom
typeset -i EXEC_HELP=0			# Display the help
typeset -i EXEC_VERB=0			# Verbosity level
typeset -i EXEC_PREOOM=0		# Should we auto trigger the oom 
typeset -i EXEC_PREOOMMEMVAL=0	# Minimum memory free bytes before auto trigger
typeset -i EXEC_PREOOMSWPVAL=0	# Minimum swap free bytes before auto trigger

# String vars
PATH_LOGFILE="/var/log/oom_manager.log"
PATH_PROFILES=profiles.d
PATH_SCORING="$(dirname $0)/oom_scoring.sh"
USER_SCORING=nobody
EXEC_PREOOMMEMSTR=""
EXEC_PREOOMSWPSTR=""


typeset -i OPTS_ERR=0
while getopts ":s:S:p:l:c:f:F:Ldtvh" opt; do
	case $opt in

	# Logfile : Set the log output file
	l)
		PATH_LOGFILE=$OPTARG
		;;
	# Log : Syslog facility to send to
	L)
		LOG_TO_SYS=1
		[ -n "$OPTARG" ] && {
			LOG_SYS_FACILITY="$OPTARG"
		}
		;;

	# sleep : Set the sleep time between 2 runs
	s)
		LOOP_SLEEP=$OPTARG
		;;

	# Count : Set the max number of loops
	c)
		LOOP_MAX=$OPTARG
		;;
	
	# Daemonize : equivalent to c=-1
	d)
		LOOP_DAEMON=1
		;;
	
	# Scoring : Exec this script as scoring process
	S)
		PATH_SCORING=$OPTARG
		;;

	# Profiles : Add a path to profiles scripts
	p)
		PATH_PROFILES="${PATH_PROFILES} $OPTARG"
		;;
	
	# Free limit : 
	f) 
		EXEC_PREOOMMEMSTR=$OPTARG
		;;

	# Free Swap limit :
	F)
		EXEC_PREOOMSWPSTR=$OPTARG
		;;

	# Trigger : Call OOM-through sysrq
	t)
		EXEC_OOM=1
		;;

	# H4lp !
	h)
		EXEC_HELP=1
		;;
	# Verbosity : increase the verbosity level
	v)
		EXEC_VERB=EXEC_VERB+1
		;;
	# Wrong opt...
	\?)
		echo "Invalid option -$OPTARG"
		OPTS_ERR=OPTS_ERR+1
		;;
	esac
done

# Exporting verbose level for oom_libs.sh
[ $EXEC_VERB -ge 2 ] && export LOG_TO_DBG=1
[ $EXEC_VERB -ge 1 ] && export LOG_TO_OUT=1


# If daemonizing, infinite loop (and FUUUU apple)
[ $LOOP_DAEMON -eq 1 ] && {
	LOOP_MAX=-1
}


# Checking the Pre-OOM trigger value
[[ ( -n "$EXEC_PREOOMMEMSTR" ) || ( -n "$EXEC_PREOOMSWPSTR" ) ]] && {
	
	oom_getmemorytotal | while read MAXMEM MAXSWP; do
		EXEC_PREOOMMEMVAL=$(oom_transformunit "$EXEC_PREOOMMEMSTR" "$MAXMEM" )
		EXEC_PREOOMSWPVAL=$(oom_transformunit "$EXEC_PREOOMSWPSTR" "$MAXSWP" )
		[ $EXEC_PREOOMMEMVAL -gt $MAXMEM ] && {
			oom_logerr "[main] memory trigger is greater than max memory : $EXEC_PREOOMMEMVAL > $MAXMEM"
			OPTS_ERR=OPTS_ERR+1
		}
		[ $EXEC_PREOOMSWPVAL -gt $MAXSWP ] && {
			oom_logerr "[main] Swap trigger is greater than max swap : $EXEC_PREOOMSWPVAL > $MAXSWP"
			OPTS_ERR=OPTS_ERR+1
		}
	done

	# Got 0 for both is an error...
	[ $EXEC_PREOOMMEMVAL -eq 0 ] && [ $EXEC_PREOOMSWPVAL -eq 0 ] && {
		OPTS_ERR=OPTS_ERR+1
	} || {
		oom_logdbg "[main] Setting pre-trigger limits to mem $EXEC_PREOOMMEMVAL / swp $EXEC_PREOOMSWPVAL"
		EXEC_PREOOM=1
	}
}

# Need halp ?
[ $EXEC_HELP -eq 1 ] && {
		oom_usage
		exit 0;
}

#
# For next commands, we need to be root.
#
[ "$USER" != "root" ] && {
	echo "Fatal error [$0] Current \$USER is not root"
	exit 1
}

# If the output file does not exists, try to craete it
[ ! -e "$PATH_LOGFILE" ] && {
	touch "$PATH_LOGFILE" > /dev/null || {
		oom_logerr "[main] Cannot create logfile $PATH_LOGFILE"
		exit 1
	}

}

# Export for oom_libs.sh
export LOG_FILE="$PATH_LOGFILE"
oom_logdbg "[main] Setting logfile to $PATH_LOGFILE"

# Checking the oom_scoring
[ ! -x "$PATH_SCORING" ] && {
	oom_logerr "[main] PATH_SCORING = \"$PATH_SCORING\" is not a valid executable file"
	OPTS_ERR=OPTS_ERR+1
}


# If args parsing error, stop there before doing anything nasty
[ $OPTS_ERR -ne 0 ] && {
	oom_logerr "Errors detected in args parsing."
	exit 2
}



# Manual OOM Trigger
[ $EXEC_OOM -eq 1 ] && {
	oom_trigger
	exit 0
}




# Main loop
while [ $LOOP_MAX -eq -1 -o $LOOP_COUNT -lt $LOOP_MAX ] ; do
	
	# trigger the OOM before the real starvation
	[ $EXEC_PREOOM -gt 0 ] && {
		
		# Get the current limit
		oom_getmemoryusage | while read FREEMEM FREESWP; do 
			TRIG_MEM=0
			TRIG_SWP=0
			# If we are under the trigger limit
			[[ ( $EXEC_PREOOMMEMVAL -eq 0 ) || ( $FREEMEM -lt $EXEC_PREOOMMEMVAL ) ]] && TRIG_MEM=1
			[[ ( $EXEC_PREOOMSWPVAL -eq 0 ) || ( $FREESWP -lt $EXEC_PREOOMSWPVAL ) ]] && TRIG_SWP=1
			
			# Are the limits reached
			[ $(($TRIG_MEM*$TRIG_SWP)) -ne 0 ] && {
				oom_log "[main] Auto triggering killer : Mem $FREEMEM / $EXEC_PREOOMMEMVAL Swp $FREESWP / $EXEC_PREOOMSWPVAL"
				oom_trigger
			}
		done
	}

	# Reload the data scoring
	# Test if the exec score is still available
	[ ! -x "$PATH_SCORING" ] && {
		oom_logerr "[main] PATH_SCORING = \"$PATH_SCORING\" unavailable as exec file"
		sleep $LOOP_SLEEP
		continue
	}

	# Regen the scores
	oom_getprocess | $BIN_SU -s /bin/ksh -c "$PATH_SCORING \"$PATH_PROFILES\"" $USER_SCORING | while read _PID _ADJ; do
		
		# Get the old adjustement
		_OADJ="$(oom_getadj $_PID)"
		
		# If there is a diff, set the new adj
		[ "$_OADJ" != "$_ADJ" ] && {
			oom_setadj $_PID $_ADJ
		}
	done
	
	LOOP_COUNT=$LOOP_COUNT+1
	sleep $LOOP_SLEEP
done


exit 0
