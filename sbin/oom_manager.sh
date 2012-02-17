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


OOM_VERSION="0.2"

. $(dirname $0)/oom_libs.sh


function oom_usage {
	echo "Linux OOM-Killer Manager v$OOM_VERSION"
	echo "Fix OOM_Scores of selected processes"
	echo 
	echo "Usage : $0 [OPTS]"
	echo 
	echo "Options:"
	echo "  -s   Time to sleep between process check (current: $LOOP_SLEEP) "
	echo "  -c   Max number of loops (current: $LOOP_MAX)"
	echo "  -d   Daemon mode (equivalent to \"-c -1\")"
	echo "  -f   Program to execute for getting the scores (current: $PATH_SCORING)"
	echo "  -p   Add a path for profiles (current: $PATH_PROFILES)"
	echo "  -t   Test the OOM Killer feature (data displayed in /var/log/messages)"
	echo 
	echo "  -h   Display this help"
	echo
}


function oom_newscore {

	# Args checks
	[ -z "$1" -o -z "$2" -o -z "$3" ] && {
		oom_logerr "[oom_newscore] Invalid args \"$1\" \"$2\" \"$3\" "
		return 1
	}
	
}


# Opts management

typeset -i LOOP_SLEEP=60
typeset -i LOOP_MAX=1
typeset -i LOOP_COUNT=0
typeset -i LOOP_DAEMON=0
typeset -i EXEC_OOM=0
typeset -i EXEC_HELP=0

PATH_PROFILES=profiles.d
PATH_SCORING="$(dirname $0)/oom_scoring.sh"
USER_SCORING=nobody


typeset -i OPTS_ERR=0
while getopts ":s:p:c:dthf:" opt; do
	case $opt in

	# Set the sleep time between 2 runs
	s)
		LOOP_SLEEP=$OPTARG
		;;

	# Set the max number of loops
	c)
		LOOP_MAX=$OPTARG
		;;
	
	# Daemon mode, equivalent to c=-1
	d)
		LOOP_DAEMON=1
		;;
	
	# Exec this script as scoring process
	f)
		PATH_SCORING=$OPTARG
		;;

	# Add a path to profiles scripts
	p)
		PATH_PROFILES="${PATH_PROFILES} $OPTARG"
		;;
	
	# Call OOM-through sysrq
	t)
		EXEC_OOM=1
		;;
	# H4lp !
	h)
		EXEC_HELP=1
		;;

	# Wrong opt...
	\?)
		echo "Invalid option -$OPTARG"
		OPTS_ERR=OPTS_ERR+1
		;;
	esac
done

# If daemonizing, infinite loop (and FUUUU apaple)
[ $LOOP_DAEMON -eq 1 ] && {
	LOOP_MAX=-1
}


# Need halp ?
[ $EXEC_HELP -eq 1 ] && {
		oom_usage
		exit 0;
}


# For next commands, we need to be root.
[ "$USER" != "root" ] && {
	echo "Fatal error [$0] Current \$USER is not root"
	exit 1
}


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
	oom_start
	exit 0
}



# Main loop
while [ $LOOP_MAX -eq -1 -o $LOOP_COUNT -lt $LOOP_MAX ] ; do
	

	# Reload the data scoring
	# Test if the exec score is still available
	[ ! -x "$PATH_SCORING" ] && {
		oom_logerr "[main] PATH_SCORING = \"$PATH_SCORING\" unavailable as exec file"
		sleep $LOOP_SLEEP
		continue
	}

	# Regen the scores
	oom_getprocess | $BIN_SU -c "$PATH_SCORING \"$PATH_PROFILES\"" $USER_SCORING | while read _PID _ADJ; do
		
		# Get the old adjustement
		_OADJ="$(oom_getadj $_PID)"
		
		# If there is a diff, set the new adj
		[ "$_OADJ" != "$_ADJ" ] && {
			
			oom_setadj $_PID $_ADJ
			oom_log "[SET] $_PID set from $_OADJ to $_ADJ"
		}
	done
	
	LOOP_COUNT=$LOOP_COUNT+1
	sleep $LOOP_SLEEP
done


exit 0
