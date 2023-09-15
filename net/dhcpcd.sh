# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Copyright (c) 2020 Gentoo Authors
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

dhcpcd_depend()
{
	after interface
	program dhcpcd
	provide dhcp

	# We prefer dhcpcd over these
	after udhcpc pump dhclient
}

_config_vars="$_config_vars dhcp dhcpcd"

dhcpcd_start()
{
	# check for pidfile after we gathered the user's args because they can
	# alter the pidfile's name (#718114)
	# Save the args into a file so dhcpcd_stop can later re-use the very
	# same args later.
	local args= opt= pidfile= opts= argsfile=/run/netifrc_dhcpcd_${IFACE}_args
	eval args=\$dhcpcd_${IFVAR}
	[ -z "${args}" ] && args=${dhcpcd}
	echo "${args}" > ${argsfile}
	pidfile="$(dhcpcd -P ${args} ${IFACE})"

	# Get our options
	eval opts=\$dhcp_${IFVAR}
	[ -z "${opts}" ] && opts=${dhcp}

	case "$(dhcpcd --version | head -n 1)" in
		"dhcpcd "[123]\.*)
			eerror 'The dhcpcd version is too old. Please upgrade.'
			return 1
			;;
	esac

	# Map some generic options to dhcpcd
	for opt in ${opts}; do
		case "${opt}" in
			nodns)
				args="${args} -C resolv.conf"
				;;
			nontp)
				args="${args} -C ntp.conf"
				;;
			nonis)
				args="${args} -C yp.conf"
				;;
			nogateway) args="${args} -G";;
			nosendhost) args="${args} -h ''";
		esac
	done

	# Add our route metric if not given
	case " ${args} " in
	*" -m "*) ;;
	*) [ "${metric:-0}" != 0 ] && args="${args} -m ${metric}";;
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
	local args= pidfile= opts= sig=SIGTERM argsfile=/run/netifrc_dhcpcd_${IFACE}_args

	# check for pidfile after we gathered the user's args because they can
	# alter the pidfile's name (#718114)
	if [ -f "${argsfile}" ] ; then
		args="$(cat ${argsfile})"
	else
		eval args=\$dhcpcd_${IFVAR}
		[ -z "${args}" ] && args=${dhcpcd}
	fi
	pidfile="$(dhcpcd -P ${args} ${IFACE})"
	[ ! -f "${pidfile}" ] && return 0

	ebegin "Stopping dhcpcd on ${IFACE}"
	eval opts=\$dhcp_${IFVAR}
	[ -z "${opts}" ] && opts=${dhcp}
	case " ${opts} " in
		*" release "*) dhcpcd -k ${args} "${IFACE}" ;;
		*) dhcpcd -x ${args} "${IFACE}" ;;
	esac
	[ -f "${argsfile}" ] && rm -f "${argsfile}"
	eend $?
}
