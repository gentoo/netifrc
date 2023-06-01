# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

ipppd_depend()
{
	program start ipppd
	after macnet
	before interface
	provide isdn
}

_config_vars="$_config_vars ipppd"

ipppd_pre_start()
{
	local opts= pidfile="/run/ipppd-${IFACE}.pid"

	# Check that we are a valid ippp interface
	case "${IFACE}" in
		ippp[0-9]*);;
		*) return 0;;
	esac

	# Check that the interface exists
	_exists || return 1

	# Might or might not be set in conf.d/net
	eval opts=\$ipppd_${IFVAR}

	einfo "Starting ipppd for ${IFACE}"
	start-stop-daemon --start --exec ipppd \
		--pidfile "${pidfile}" \
		-- ${opts} pidfile "${pidfile}" \
		file "/etc/ppp/options.${IFACE}" >/dev/null
	eend $?
}

ipppd_post_stop()
{
	local pidfile="/run/ipppd-${IFACE}.pid"

	[ ! -f "${pidfile}" ] && return 0

	einfo "Stopping ipppd for ${IFACE}"
	start-stop-daemon --stop --quiet --exec ipppd \
		--pidfile "${pidfile}"
	eend $?
}
