# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

dhclient_depend()
{
	after interface
	program start dhclient
	provide dhcp

	# We prefer dhclient over these
	after udhcpc pump
}

_config_vars="$_config_vars dhcp dhcpcd"

dhclient_start()
{
	local args= opt= opts= pidfile="/run/dhclient-${IFACE}.pid"
	local sendhost=true dconf=

	# Get our options
	# These options only work in Gentoo, and maybe RedHat
	eval args=\$dhclient_${IFVAR}
	eval opts=\$dhcp_${IFVAR}
	[ -z "${opts}" ] && opts=${dhcp}

	for opt in ${opts}; do
		case "${opt}" in
			nodns) args="${args} -e PEER_DNS=no";;
			nontp) args="${args} -e PEER_NTP=no";;
			nogateway) args="${args} -e PEER_ROUTERS=no";;
			nosendhost) sendhost=false;;
		esac
	done

	# Add our route metric
	[ "${metric:-0}" != "0" ] && args="${args} -e IF_METRIC=${metric}"

	if ${sendhost}; then
		local hname="$(hostname)"
		if [ "${hname}" != "(none)" -a "${hname}" != "localhost" ]; then
			dhconf="${dhconf} interface \"${IFACE}\" {"
			dhconf="${dhconf} send host-name \"${hname}\";"
			dhconf="${dhconf}}"
		fi
	fi

	# Bring up DHCP for this interface
	ebegin "Running dhclient"
	echo "${dhconf}" | start-stop-daemon --start --exec dhclient \
		--pidfile "${pidfile}" \
		-- ${args} -q -1 -pf "${pidfile}" "${IFACE}"
	eend $? || return 1

	_show_address
	return 0
}

dhclient_stop()
{
	local pidfile="/run/dhclient-${IFACE}.pid" opts=
	[ ! -f "${pidfile}" ] && return 0

	# Get our options
	if command -v dhclient >/dev/null; then
		eval opts=\$dhcp_${IFVAR}
		[ -z "${opts}" ] && opts=${dhcp}
	fi

	ebegin "Stopping dhclient on ${IFACE}"
	case " ${opts} " in
		*" release "*) dhclient -q -r -pf "${pidfile}" "${IFACE}";;
		*)
			start-stop-daemon --stop --quiet \
				--exec dhclient --pidfile "${pidfile}"
			;;
	esac
	eend $?
}
