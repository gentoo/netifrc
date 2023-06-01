# Copyright (c) 2004-2007 Gentoo Foundation
# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

adsl_depend()
{
	program adsl-start pppoe-start
	before dhcp
}

adsl_setup_vars()
{
	local startstop="$1" cfgexe=

	if command -v pppoe-start >/dev/null; then
		exe="pppoe-${startstop}"
		cfgexe=pppoe-setup
	else
		exe="adsl-${startstop}"
		cfgexe=adsl-setup
	fi

	# Decide which configuration to use.  Hopefully there is an
	# interface-specific one
	cfgfile="/etc/ppp/pppoe-${IFACE}.conf"
	[ -f "${cfgfile}" ] || cfgfile="/etc/ppp/pppoe.conf"

	if [ ! -f "${cfgfile}" ]; then
		eerror "no pppoe.conf file found!"
		eerror "Please run ${cfgexe} to create one"
		return 1
	fi

	return 0
}

adsl_start()
{
	local exe= cfgfile= user=

	adsl_setup_vars start || return 1

	# Might or might not be set in conf.d/net
	eval user=\$adsl_user_${IFVAR}

	# Start ADSL with the cfgfile, but override ETH and PIDFILE
	einfo "Starting ADSL for ${IFACE}"
	(
	cat "${cfgfile}";
	echo "ETH=${IFACE}";
	echo "PIDFILE=/run/rp-pppoe-${IFACE}.pid";
	[ -n "${user}" ] && echo "USER=${user}";
	) | ${exe} >/dev/null
	eend $?
}

adsl_stop()
{
	local exe= cfgfile=

	[ ! -f /run/rp-pppoe-"${IFACE}".pid ] && return 0

	adsl_setup_vars stop || return 1

	einfo "Stopping ADSL for ${IFACE}"
	(
	cat "${cfgfile}";
	echo "ETH=${IFACE}";
	echo "PIDFILE=/run/rp-pppoe-${IFACE}.pid";
	) | ${exe} >/dev/null
	eend $?

	return 0
}
