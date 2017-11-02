Name:		oom_manager
Version:	0.6
Release:	1%{?dist}
Summary:	Configure and manage Linux Out-Of-Memory killer

Group:		Application/System
License:	GPL-3
BuildArch:	noarch
URL:		https://github.com/saruspete/oom_manager
Source0:	https://github.com/saruspete/%{name}/archive/%{version}.tar.gz

#BuildRequires:
Requires:	gawk

%define		debug_package %{nil}

# You can try to push files in /usr/local or /opt
%define		_prefix		/


# Systemd
%if 0%{?fedora} || 0%{?rhel} >= 7 || 0%{?suse_version} >= 1140
%define		with_systemd	1

%define		my_scriptlet_post	%{systemd_post}
%define		my_scriptlet_preun	%{systemd_preun}
%define		my_scriptlet_postun	%{systemd_postun}

# rcinit
%else
%define		with_systemd	0

%define		my_scriptlet_post	/sbin/chkconfig --add %{name}
%define		my_scriptlet_preun	if [ $1 = 0 ]; then \
	/sbin/service %{name} stop >/dev/null 2>&1 \
	/sbin/chkconfig --del %{name} \
fi
%define		my_scriptlet_postun	if [ $1 != 0 ]; then \
	/sbin/service %{name} condrestart >/dev/null 2>&1 \
fi

%endif


# =============================================================================
# Complete description of the package
# =============================================================================
%description


# =============================================================================
# Preparation of the build environment
# =============================================================================
%prep

%setup -q

# =============================================================================
# Compilation of the source
# =============================================================================
%build


# =============================================================================
# Installation from build to buildroot
# =============================================================================
%install

rm -rf "${RPM_BUILD_ROOT}"
mkdir -p "${RPM_BUILD_ROOT}%{?prefix}/"
rsync -av --exclude .git usr etc "${RPM_BUILD_ROOT}%{?prefix}/"

ls -al


# Deploy systemd service
%if %{with_systemd}
install -m 755 -d "${RPM_BUILD_ROOT}%{_unitdir}"
install -m 644 -p goodies/%{name}.service \
				"${RPM_BUILD_ROOT}%{_unitdir}/%{name}.service"

# Or deploy sysinit service
%else
install -m 755 -d "${RPM_BUILD_ROOT}%{_sysconfdir}/rc.d/init.d"
install -m 755 -p goodies/%{name}.rcinit \
				"${RPM_BUILD_ROOT}%{_sysconfdir}/rc.d/init.d/%{name}"

%endif

# =============================================================================
# Cleanup of the build environment
# =============================================================================
#%clean


# =============================================================================
# Files to be embedded in final RPM
# =============================================================================
%files
%defattr(-,root,root)

%config %{_sysconfdir}/sysconfig/%{name}

# Standard files
%{?prefix}/etc/%{name}
%{?prefix}/usr/sbin/*.sh


%doc %{_prefix}/usr/share/man/man8

# Init script
%if %{with_systemd}
%{_unitdir}/%{name}.service
%else
%{_sysconfdir}/rc.d/init.d/%{name}
%endif


# =============================================================================
# Actions before installation / upgrade
# =============================================================================
%pre

# =============================================================================
# Actions after installation / upgrade
# =============================================================================
%post
%{my_scriptlet_post}

# =============================================================================
# Actions before removal
# =============================================================================
%preun
%{my_scriptlet_preun}

# =============================================================================
# Actions after removal
# =============================================================================
%postun
%{my_scriptlet_postun}

# =============================================================================
# Changelog
# =============================================================================
%changelog

