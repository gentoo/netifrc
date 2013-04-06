# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.

dhclientv6_depend()
{
	after interface
	program start /sbin/dhclient
	provide dhcpv6
}

_config_vars="$_config_vars dhcp dhclient dhcpv6 dhclientv6"

dhclientv6_start()
{
	local args= opt= opts= pidfile="/var/run/dhclientv6-${IFACE}.pid"
	local sendhost=true dconf=

	# Get our options
	# These options only work in Gentoo, and maybe RedHat
	eval args=\$dhclientv6_${IFVAR}
	[ -z "${args}" ] && eval args=\$dhclient_${IFVAR}
	eval opts=\$dhcpv6_${IFVAR}
	[ -z "${opts}" ] && opts=${dhcpv6}
	[ -z "${opts}" ] && eval opts=\$dhcp_${IFVAR}
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
			dhconf="${dhconf} send fqdn.fqdn \"${hname}\";"
			dhconf="${dhconf} send fqdn.encoded on;"
			dhconf="${dhconf} send fqdn.server-update on;"
			dhconf="${dhconf} send fqdn.no-client-update on;"
			dhconf="${dhconf}}"
		fi
	fi

	# Bring up DHCP for this interface
	ebegin "Running dhclient -6"
	echo "${dhconf}" | start-stop-daemon --start --exec /sbin/dhclient \
		--pidfile "${pidfile}" \
		-- -6 ${args} -q -1 -pf "${pidfile}" "${IFACE}"
	eend $? || return 1

	_show_address6
	return 0
}

dhclientv6_stop()
{
	local pidfile="/var/run/dhclientv6-${IFACE}.pid" opts=
	[ ! -f "${pidfile}" ] && return 0

	# Get our options
	if [ -x /sbin/dhclient ]; then
		eval opts=\$dhcp_${IFVAR}
		[ -z "${opts}" ] && opts=${dhcp}
	fi

	ebegin "Stopping dhclient -6 on ${IFACE}"
	case " ${opts} " in
		*" release "*) dhclient -6 -q -r -pf "${pidfile}" "${IFACE}";;
		*)
			start-stop-daemon --stop --quiet \
				--exec /sbin/dhclient --pidfile "${pidfile}"
			;;
	esac
	eend $?
}
