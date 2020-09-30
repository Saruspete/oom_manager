OOM-Manager / javamine :
======================

Script to configure and manage Linux Out-Of-Memory killer.


Features :
--------
  * **Change the oom_score parameter based on patterns**. The default score script provides the following filters :
    * user (UserName)
    * uid (UserID)
    * ruid (real-UserID)
    * pid (ProcessID)
    * ppid (parent-ProcessID)
    * process (process name)
    * score (OOM-Score)
  * **Trigger OOM at defined RAM & Swap usage**. This is particularely useful to generate an OOM before all memory is used and system is totally unresponsive
  * **Logs all disruptive action** by default. Verbosity level configurable
  * Management scripts runs as *root*, while scoring script runs as user *nobody*
  * scoring script is replaceable by any application that reads stdin for processlist and outputs 


Packaging :
---------

RPM Specfile is provided in *goodies/oom_manager.spec*

To build it:

	# Ensure you have the package "rpm-build" installed.
	
	# Create the ~/rpmbuild tree
	rpmdev-setuptree -d
	
	# Downlad the latest version of goodies/oom_manager.spec to ~/rpmbuild/SPECS
	wget https://raw.githubusercontent.com/Saruspete/oom_manager/master/goodies/oom_manager.spec -O ~/rpmbuild/SPECS/oom_manager.spec
	
	# If your rpmbuild version doesn't support "source auto-download", 
	# download the target release from https://github.com/Saruspete/oom_manager/releases 
	# and put it into ~/rpmbuild/SOURCES/
	rpmbuild --undefine=_disable_source_fetch -ba ~/rpmbuild/SPECS/oom_manager.spec
	
	# Your RPM should be available in: 
	# ~/rpmbuild/RPMS/noarch/oom_manager-*.noarch.rpm
	

Manual (non-packaged) Installation
-----------------------------------

If you can't create a package, you can place the script as-is in /usr/local:

	# Set your target folder
	OOMMGR_PATH="/usr/local"
	
	# Download and extract to /usr/local
	wget https://github.com/Saruspete/oom_manager/archive/master.tar.gz -O - | tar -zxv --strip=1 -C $OOMMGR_PATH
	
	# Edit and copy the configuration to standard folder
	echo "PATH_BASE=$OOMMGR_PATH" >> $OOMMGR_PATH/etc/sysconfig/oom_manager
	mv $OOMMGR_PATH/etc/sysconfig/oom_manager /etc/sysconfig/
	
	# Copy the service file depending on the system init
	
	# systemd
	if [[ "$(</proc/1/comm)" == "systemd" ]]; then
		for unitpath in $(systemctl show | grep ^UnitPath|cut -d'=' -f 2-); do
			[[ -d $unitpath ]] || continue
			mv $OOMMGR_PATH/goodies/oom_manager.service $unitpath/ && \
				echo "Copied to $unitpath" && \
				break
		done
	
	# init-script
	else
		mv $OOMMGR_PATH/goodies/oom_manager.rcinit /etc/rc.d/init.d/oom_manager
	fi
	
	# You can now edit /etc/sysconfig/oom_manager to enable pre-oom and change its values
	# You should auto add the script to auto-start
	# systemd: systemctl enable --now oom_manager
	# initrc:  chkconfig --enable oom_manager
	
