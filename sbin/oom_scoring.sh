#!/bin/ksh

# This script recognize these elements :
# user = 
# uid = 
# ruid =
# ppid =
# pid = 
# process =
# score = 

# #############################################################################
# OOM Killer score profiler
# Adrien Mahieux <adrien.mahieux-ext@socgen.com>
# Franck Jouvanceau <franck.jouvanceau@socgen.com>
# #############################################################################
# 
# This file takes the output of "ps" as stdin, and a folder of profiles as
# parameters
#
# #############################################################################

[ "$USER" == "root" ] && {
	echo "You must not run this script as root" > /dev/stderr
	exit 1
}

[ -z "$@" ] && {
	echo "No profile path given" > /dev/stderr
	exit 1
}

PROFILESDIRS="$@"
PROFILESDIRS_ERR=""

BIN_EGREP="/bin/egrep"
BIN_AWK="/usr/bin/awk"

PROFILES=""
for PDIR in $PROFILESDIRS; do
	for PFILE in $PDIR/*; do 
		[ -e "$PFILE" ] && {
			PROFILES="$PROFILES $PFILE"
		}
	done
done

# Awk will do the job. Data is read from stdin
$BIN_AWK -v profiles="$PROFILES" '
	function getvars(line,a_var,    i,n,par,e,p) {
		n=split(line,e,"[ \t]"); #one space or tab
		for(i=1;i<=n;i++) {
			p=e[i];
			if(p~/^#/) break;
			#while (p contains xxx=" && (p not terminated by " but not \" or p is xxx=") and not eol
			while(  p~/^[^"]+="/ && (p!~/[^\\]"$/ || p~/^[^"]+="$/) && i<=n) {
				i++;
				p=p" "e[i];
			}
			sub("\"$","",p);
			sub("\"","",p);
			gsub("\\\\\"","\"",p);
			par=substr(p,1,index(p,"=")-1);
			if(par)
				a_var[par]=substr(p,index(p,"=")+1);
		}
	}
	function delete_array(a, i) {
		for (i in a) delete a[i];
	}
	
	BEGIN {
		# Read the profiles
		split (profiles,t_profiles);
		i=1
		for (i_pro in t_profiles) {
			profile=t_profiles[i_pro]
			# Get all lines
			while (getline<profile >0) {
				if ($0~/^[\s]*$|^#/) { 
					continue; 
				}
				filters[i]=$0
				i++
			}
			close(profile)
		}

	}
	
	# each line is a process entry
	{
		score_new=NULL
		score_cur=NULL
		for (line in filters) {
			matching=1	
			cmd=substr($0, index($0,$6))
			
			getvars(filters[line], t_tuples);
			for (i in t_tuples) {
				
				var = i
				val = t_tuples[var]
								
				if (var == "pid"	&& !match($1,val))	matching=0
				if (var == "ppid"	&& $2 != val)		matching=0
				if (var == "user"	&& !match($3,val))	matching=0
				if (var == "uid"	&& $4 != val)		matching=0
				if (var == "ruid"	&& $5 != val)		matching=0
				if (var =="process"	&& !match(cmd,val))		matching=0
				if (var == "score")						score_new=val


			}
			delete_array(t_tuples)
			
			# If the process has matched, update the new score if better
			if (matching) {
				# If the line matched a valid score element
				if (score_new != NULL) {
					# If the new score is better than the current
					if (score_cur == NULL || 
						score_cur <= 0 && score_new < score_cur ||
						score_cur > 0 && socre_new > score_cur ) {
						
						# Set the new current score
						score_cur = score_new
					}
				}
			}
		}
		if (score_cur != NULL) {
			print $1,score_cur
		}
	}
'
return $?
