# Copyright (c) 2015 Gentoo Foundation
# All rights reserved. Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

hsr_depend()
{
	program ip
	after interface
	before dhcp macchanger
}

_is_hsr() {
	is_interface_type hsr
}

hsr_pre_start()
{
	local hsr=
	eval hsr=\$type_${IFVAR}
	[ "${hsr}" = "hsr" ] || return 0
	eval hsr_slave1=\$hsr_slave1_${IFVAR}
	eval hsr_slave2=\$hsr_slave2_${IFVAR}
	eval hsr_supervision=\$hsr_supervision_${IFVAR}
	eval hsr_version=\$hsr_version_${IFVAR}
	eval hsr_proto=\$hsr_proto_${IFVAR}
	if [ -z "${hsr_slave1}" ] || [ -z "${hsr_slave2}" ]; then
		eerror "HSR interfaces require two slave interfaces to be set"
		return 1
	fi
	if ! ( IFACE=${hsr_slave1} _exists ); then
		eerror "HSR slave1 ${hsr_slave1} does not exist"
		return 1
	fi
	if ! ( IFACE=${hsr_slave2} _exists ); then
		eerror "HSR slave2 ${hsr_slave2} does not exist"
		return 1
	fi

	ebegin "Creating HSR interface ${IFACE}"
	cmd="ip link add name "${IFACE}" type hsr slave1 ${hsr_slave1} slave2 ${hsr_slave2}"
	test -n "${hsr_supervision}" && cmd="${cmd} supervision ${hsr_supervision}"
	test -n "${hsr_version}" && cmd="${cmd} version ${hsr_version}"
	test -n "${hsr_proto}" && cmd="${cmd} proto ${hsr_proto}"
	veinfo $cmd
	if $cmd ; then
		eend 0 && _up && set_interface_type hsr
	else
		eend 1
	fi
}


hsr_post_stop()
{
	_is_hsr || return 0

	ebegin "Removing HSR ${IFACE}"
	cmd="ip link delete "${IFACE}" type hsr"
	veinfo "$cmd"
	$cmd
	eend $?
}
