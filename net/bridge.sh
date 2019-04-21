# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

bridge_depend()
{
	before interface macnet
	program brctl ip
}

_config_vars="$_config_vars bridge bridge_add brctl"

_is_bridge()
{
	[ -d /sys/class/net/"${1:-${IFACE}}"/bridge ]
	return $?
}

_is_bridge_port()
{
	[ -d /sys/class/net/"${1:-${IFACE}}"/brport ]
	return $?
}

_bridge_ports()
{
	for x in /sys/class/net/"${1:-${IFACE}}"/brif/*; do
		n=${x##*/}
		echo $n
	done
}

bridge_pre_start()
{
	local brif= oiface="${IFACE}" e= x=
	# ports is for static add
	local ports="$(_get_array "bridge_${IFVAR}")"
	# old config options
	local brctl_opts="$(_get_array "brctl_${IFVAR}")"
	# brif is used for dynamic add
	eval brif=\$bridge_add_${IFVAR}

	local do_iproute2=false do_brctl=false
	if [ -n "${brctl_opts}" ] && type brctl >/dev/null 2>&1; then
		do_brctl=true
	elif type ip >/dev/null 2>&1; then
		do_iproute2=true
	elif type brctl >/dev/null 2>&1; then
		do_brctl=true
	fi

	# we need a way to if the bridge exists in a variable name, not just the
	# contents of a variable. Eg if somebody has only bridge_add_eth0='br0',
	# with no other lines mentioning br0.
	eval bridge_unset=\${bridge_${IFVAR}-y\}
	eval brctl_unset=\${brctl_${IFVAR}-y\}
	eval bridge_force_unset=\${bridge_force_${IFVAR}-y\}

	if [ -z "${brif}" -a "${brctl_unset}${bridge_force_unset}" = 'yy' ]; then
		if [ -z "${ports}" -a "${bridge_unset}" = "y" ]; then
			#eerror "Misconfigured static bridge detected (see net.example)"
			return 0
		fi
	fi

	# If the bridge was already up, we should clear it
	[ "${bridge_unset}" != "y" ] && bridge_post_stop

	(
	# Normalize order of variables
	if [ -z "${ports}" -a -n "${brif}" ]; then
		# Dynamic mode detected
		ports="${IFACE}"
		IFACE="${brif}"
		IFVAR=$(shell_var "${IFACE}")
	else
		# Static mode detected
		ports="${ports}"
		metric=1000
	fi

	if ! _is_bridge ; then
		ebegin "Creating bridge ${IFACE}"
		if ${do_iproute2}; then
			ip link add "${IFACE}" type bridge
			rc=$?
		elif ${do_brctl}; then
			brctl addbr "${IFACE}"
			rc=$?
		else
			eerror "Neither iproute2 nor brctl has been found, please install"
			eerror "either \"iproute2\" or \"brctl\"."
			rc=1
		fi
		if [ ${rc} != 0 ]; then
			eend 1
			return 1
		fi
	fi

	# TODO: does this reset the bridge every time we add a interface to the
	# bridge? We should probably NOT do that.

	# Old configuration set mechanism
	# Only a very limited subset of the options are available in the old
	# configuration method. The sysfs interface is in the next block instead.
	if ${do_brctl}; then
		if [ -n "${brctl_opts}" ]; then
			ewarn "brctl options are deprecated please migrate to sysfs options"
			ewarn "map of important options is available at https://wiki.gentoo.org/wiki/Netifrc/Brctl_Migration"

			local IFS="$__IFS"
			for x in ${brctl_opts}; do
				unset IFS
				set -- ${x}
				x=$1
				shift
				set -- "${x}" "${IFACE}" "$@"
				brctl "$@"
			done
			unset IFS
		fi
	fi

	# New configuration set mechanism, matches bonding
	for x in /sys/class/net/"${IFACE}"/bridge/*; do
		[ -f "${x}" ] || continue
		n=${x##*/}
		# keep no prefix for backward compatibility
		for prefix in "" bridge_; do
			eval s=\$${prefix}${n}_${IFVAR}
			if [ -n "${s}" ]; then
				[ -z "${prefix}" ] && ewarn "sysfs key '${n}_${IFVAR}' should be prefixed, please add bridge_ prefix."
				einfo "Setting ${n}: ${s}"
				echo "${s}" >"${x}" || \
				eerror "Failed to configure $n (${n}_${IFVAR})"
			fi
		done
	done

	if [ -n "${ports}" ]; then
		einfo "Adding ports to ${IFACE}"
		eindent

		local BR_IFACE="${IFACE}"
		for x in ${ports}; do
			ebegin "${x}"
			local IFACE="${x}"
			local IFVAR=$(shell_var "${IFACE}")
			if ! _exists "${IFACE}" ; then
				eerror "Cannot add non-existent interface ${IFACE} to ${BR_IFACE}"
				return 1
			fi
			# The interface is known to exist now
			_up
			if ${do_iproute2}; then
				ip link set "${x}" master "${BR_IFACE}"
			elif ${do_brctl}; then
				brctl addif "${BR_IFACE}" "${x}"
			fi
			if [ $? != 0 ]; then
				eend 1
				return 1
			fi
			# Per-interface bridge settings
			for x in /sys/class/net/"${IFACE}"/brport/*; do
				[ -f "${x}" ] || continue
				n=${x##*/}
				for prefix in "" brport_; do
					eval s=\$${prefix}${n}_${IFVAR}
					if [ -n "${s}" ]; then
						[ -z "${prefix}" ] && ewarn "sysfs key '${n}_${IFVAR}' should be prefixed, please add brport_ prefix."
						einfo "Setting ${n}@${IFACE}: ${s}"
						echo "${s}" >"${x}" || \
						eerror "Failed to configure $n (${n}_${IFVAR})"
					fi
				done
			done
			eend 0
		done
		eoutdent
	fi
	) || return 1

	# Bring up the bridge
	_set_flag promisc
	_up
}

bridge_post_stop()
{
	local port= ports= delete=false extra=

	if _is_bridge "${IFACE}"; then
		ebegin "Destroying bridge ${IFACE}"
		_down
		for x in /sys/class/net/"${IFACE}"/brif/*; do
			[ -s $x ] || continue
			n=${x##*/}
			ports="${ports} ${n}"
		done
		delete=true
		iface=${IFACE}
		eindent
	else
		# We are taking down an interface that is part of a bridge maybe
		ports="${IFACE}"
		local brport_dir="/sys/class/net/${IFACE}/brport"
		[ -d ${brport_dir} ] || return 0
		iface=$(readlink ${brport_dir}/bridge)
		iface=${iface##*/}
		[ -z "${iface}" ] && return 0
		extra=" from ${iface}"
	fi

	for port in ${ports}; do
		ebegin "Removing port ${port}${extra}"
		local IFACE="${port}"
		_set_flag -promisc
		if type ip > /dev/null 2>&1; then
			ip link set "${port}" nomaster
		else
			brctl delif "${iface}" "${port}"
		fi
		eend $?
	done

	if ${delete}; then
		eoutdent
		if type ip > /dev/null 2>&1; then
			ip link del "${iface}"
		else
			brctl delbr "${iface}"
		fi
		eend $?
	fi

	return 0
}
