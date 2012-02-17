#!/bin/ksh


LOG_TO_OUT="${LOG_TO_OUT:-0}"
LOG_TO_FILE="${LOG_TO_FILE:-1}"
LOG_FILE="${FILE_LOGERR:-/var/log/oom_manager.log}"


BIN_PS=/bin/ps
BIN_AWK=/usr/bin/awk
BIN_SED=/bin/sed
BIN_CAT=/bin/cat
BIN_SU=/bin/su

function oom_logerr {
	DATE="$(date +%y-%m-%d_%H:%M:%S)"
	[ "$LOG_TO_OUT" = "1" ]  && { echo "[$DATE] [ERR] $@" > /dev/stderr ; }
	[ "$LOG_TO_FILE" = "1" ] && { echo "[$DATE] [ERR] $@" >> $LOG_FILE ; }
}

function oom_log {
	DATE="$(date +%y-%m-%d_%H:%M:%S)"
	[ "$LOG_TO_OUT" = "1" ]  && { echo "[$DATE] [STD] $@" ; }
	[ "$LOG_TO_FILE" = "1" ] && { echo "[$DATE] [STD] $@" >> $LOG_FILE ; }
}


function oom_setadj {

	[ -z "$1" ] && { 
		oom_logerr "[oom_setadj] Wrong PID arg given \"$1\""
		return 1
	}
	[ -z "$2" -o "$2" -lt -15 -o "$2" -gt 17 ] && {
		oom_logerr "[oom_setadj] Wrong Score given \"$2\""
	}
	
	PID=$1
	SCORE=$2
	[ ! -d "/proc/$PID/" ] && {
		oom_logerr "[oom_setadj] Path does not exists /proc/$PID/"
		return 1
	}
	
	# Set the score
	echo "$SCORE" > /proc/$PID/oom_adj

	# Check if scoring was successful
	[ "$($BIN_CAT /proc/$PID/oom_adj)" -eq "$SCORE" ] && return 0

	# Not returned yet ? SHITSHITSHITSHITSHIT
	return 1
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
	
	$BIN_PS -ewww -o pid,ppid,user,uid,ruid,gid,rgid,args | 
	$BIN_SED -e 's/  */ /g' -e 's/^ *//'
#	$BIN_AWK '{print substr($0, index($1,$7)) }'
	
}

