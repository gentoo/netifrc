# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

dhcpcd_depend()
{
	after interface
	program start dhcpcd
	provide dhcp

	# We prefer dhcpcd over these
	after udhcpc pump dhclient
}

_config_vars="$_config_vars dhcp dhcpcd"

dhcpcd_start()
{
	# check for pidfile after we gathered the user's opts because they can
	# alter the pidfile's name (#718114)
	local args= opt= pidfile= opts= new=true
	eval args=\$dhcpcd_${IFVAR}
	[ -z "${args}" ] && args=${dhcpcd}
	pidfile="$(dhcpcd -P ${args} ${IFACE})"

	# Get our options
	eval opts=\$dhcp_${IFVAR}
	[ -z "${opts}" ] && opts=${dhcp}

	case "$(dhcpcd --version)" in
		"dhcpcd "[123]*) new=false;;
	esac

	# Map some generic options to dhcpcd
	for opt in ${opts}; do
		case "${opt}" in
			nodns)
				if ${new}; then
					args="${args} -C resolv.conf"
				else
					args="${args} -R"
				fi
				;;
			nontp)
				if ${new}; then
					args="${args} -C ntp.conf"
				else
					args="${args} -N"
				fi
				;;
			nonis)
				if ${new}; then
					args="${args} -C yp.conf"
				else
					args="${args} -Y"
				fi
				;;
			nogateway) args="${args} -G";;
			nosendhost) args="${args} -h ''";
		esac
	done

	# Add our route metric if not given
	case " $args " in
	*" -m "*) ;;
	*) [ "${metric:-0}" != 0 ] && args="$args -m $metric";;
	esac

	# Bring up DHCP for this interface
	ebegin "Running dhcpcd"

	eval dhcpcd "${args}" "${IFACE}"
	eend $? || return 1

	_show_address
	return 0
}

dhcpcd_stop()
{
	local args= pidfile= opts= sig=SIGTERM

	# check for pidfile after we gathered the user's opts because they can
	# alter the pidfile's name (#718114)
	eval args=\$dhcpcd_${IFVAR}
	[ -z "${args}" ] && args=${dhcpcd}
	pidfile="$(dhcpcd -P ${args} ${IFACE})"
	[ ! -f "${pidfile}" ] && return 0

	ebegin "Stopping dhcpcd on ${IFACE}"
	eval opts=\$dhcp_${IFVAR}
	[ -z "${opts}" ] && opts=${dhcp}
	case " ${opts} " in
		*" release "*) dhcpcd -k "${IFACE}" ;;
		*) dhcpcd -x "${IFACE}" ;;
	esac
	eend $?
}
