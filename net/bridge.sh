# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.

bridge_depend()
{
	before interface macnet
	program ip brctl
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

_brctl()
{
	if [ -z "${_bridge_use_ip}" ]; then
	       if ip -V >/dev/null 2>&1 && [ "$(ip -V | cut -c 24-29)" -ge 130430 ]; then
			_bridge_use_ip=1
		else
			_bridge_use_ip=0
		fi
	fi
	if [ "${_bridge_use_ip}" -eq 1 ]; then
		case "$1" in
			addbr)
				ip link add "$2" type bridge
				;;
			delbr)
				ip link del "$2"
				;;
			addif)
				ip link set "$3" master "$2"
				;;
			delif)
				ip link set "$3" nomaster
				;;
			setageing)
				echo "$3" > /sys/class/net/"$2"/bridge/ageing_time
				;;
			setgcint)
				# appears to have been dropped in Debian, and I don't see a sysfs file for it
				eerror "brctl setgcint is not supported!"
				return 1
				;;
			stp)
				if [ "$3" = "on" -o "$3" = "yes" -o "$3" = "1" ]; then
					_stp_state=1
				elif [ "$3" = "off" -o "$3" = "no" -o "$3" = "0" ]; then
					_stp_state=0
				else
					eerror "Invalid STP state for brctl stp!"
					return 1
				fi
				echo ${_stp_state} > /sys/class/net/"$2"/bridge/stp_state
				;;
			setbridgeprio)
				echo "$3" > /sys/class/net/"$2"/bridge/priority
				;;
			setfd)
				echo "$3" > /sys/class/net/"$2"/bridge/forward_delay
				;;
			sethello)
				echo "$3" > /sys/class/net/"$2"/bridge/hello_time
				;;
			setmaxage)
				echo "$3" > /sys/class/net/"$2"/bridge/max_age
				;;
			setpathcost)
				echo "$4" > /sys/class/net/"$2"/brif/"$3"/path_cost
				;;
			setportprio)
				echo "$4" > /sys/class/net/"$2"/brif/"$3"/priority
				;;
			hairpin)
				if [ "$4" -eq "on" -o "$4" -eq "yes" -o "$4" -eq "1" ]; then
					_hairpin_mode=1
				elif [ "$4" -eq "off" -o "$4" -eq "no" -o "$4" -eq "0" ]; then
					_hairpin_mode=0
				else
					eerror "Invalid hairpin mode for brctl hairpin!"
					return 1
				fi
				echo ${_hairpin_mode} > /sys/class/net/"$2"/brif/"$3"/hairpin_mode
				;;
		esac
	else
		brctl "$@"
	fi
}

bridge_pre_start()
{
	local brif= oiface="${IFACE}" e= x=
	# ports is for static add
	local ports="$(_get_array "bridge_${IFVAR}")"
	# old config options
	local opts="$(_get_array "brctl_${IFVAR}")"
	# brif is used for dynamic add
	eval brif=\$bridge_add_${IFVAR}

	# we need a way to if the bridge exists in a variable name, not just the
	# contents of a variable. Eg if somebody has only bridge_add_eth0='br0',
	# with no other lines mentioning br0.
	eval bridge_unset=\${bridge_${IFVAR}-y\}
	eval brctl_unset=\${brctl_${IFVAR}-y\}

	if [ -z "${brif}" -a "${brctl_unset}" = 'y' ]; then
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
		if ! _brctl addbr "${IFACE}"; then
			eend 1
			return 1
		fi
	fi

	# TODO: does this reset the bridge every time we add a interface to the
	# bridge? We should probably NOT do that.

	# Old configuration set mechanism
	# Only a very limited subset of the options are available in the old
	# configuration method. The sysfs interface is in the next block instead.
	local IFS="$__IFS"
	for x in ${opts}; do
		unset IFS
		set -- ${x}
		x=$1
		shift
		set -- "${x}" "${IFACE}" "$@"
		_brctl "$@"
	done
	unset IFS

	# New configuration set mechanism, matches bonding
	for x in /sys/class/net/"${IFACE}"/bridge/*; do
		[ -f "${x}" ] || continue
		n=${x##*/}
		eval s=\$${n}_${IFVAR}
		if [ -n "${s}" ]; then
			einfo "Setting ${n}: ${s}"
			echo "${s}" >"${x}" || \
			eerror "Failed to configure $n (${n}_${IFVAR})"
		fi
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
			if ! _brctl addif "${BR_IFACE}" "${x}"; then
				eend 1
				return 1
			fi
			# Per-interface bridge settings
			for x in /sys/class/net/"${IFACE}"/brport/*; do
				[ -f "${x}" ] || continue
				n=${x##*/}
				eval s=\$${n}_${IFVAR}
				if [ -n "${s}" ]; then
					einfo "Setting ${n}@${IFACE}: ${s}"
					echo "${s}" >"${x}" || \
					eerror "Failed to configure $n (${n}_${IFVAR})"
				fi
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
		_brctl delif "${iface}" "${port}"
		eend $?
	done

	if ${delete}; then
		eoutdent
		_brctl delbr "${iface}"
		eend $?
	fi

	return 0
}
