#!/bin/sh
#
# net.sh: udev external RUN script
#
# Copyright 2007 Roy Marples <uberlord@gentoo.org>
# Distributed under the terms of the GNU General Public License v2

IFACE=$1
ACTION=$2

SCRIPT=/etc/init.d/net.$IFACE

# make sure openrc is managing services
if [ ! -d /run/openrc ]; then
	exit 0
fi

# ignore interfaces that are registered after being "up" (?)
case ${IFACE} in
	ppp*|ippp*|isdn*|plip*|lo*|irda*|dummy*|ipsec*|tun*|tap*|br*|macvtap*|ipvl*|vlan*|vxlan*|peth*|ifb*|veth*|gre*|vrf*|wg*)
		exit 0 ;;
esac

is_service_enabled() {
	local svc="$1"
	[ ! -e "/etc/init.d/${svc}" ] && return 1
	[ -e "/etc/runlevels/boot/${svc}" ] && return 0
	[ -e "/etc/runlevels/default/${svc}" ] && return 0
	[ -e "/etc/runlevels/sysinit/${svc}" ] && return 0
	return 1
}

# stop here if OpenRC's so called "newnet" is enabled, bug #503530
if is_service_enabled network; then
	exit 0
fi

# stop here if coldplug is disabled, Bug #206518
if [ "${do_not_run_plug_service}" = 1 ]; then
	exit 0
fi

if [ ! -x "${SCRIPT}" ] ; then
	#do not flood log with messages, bug #205687
	#logger -t udev-net.sh "${SCRIPT}: does not exist or is not executable"
	exit 1
fi

# If we're stopping then sleep for a bit in-case a daemon is monitoring
# the interface. This to try and ensure we stop after they do.
[ "${ACTION}" = "stop" ] && sleep 2

IN_HOTPLUG=1 "${SCRIPT}" --quiet "${ACTION}"
