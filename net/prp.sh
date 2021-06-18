# Copyright (c) 2015 Gentoo Foundation
# All rights reserved. Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

prp_depend()
{
	program ip
	after interface
	before dhcp macchanger
}

_is_prp() {
	is_interface_type prp
}

prp_pre_start()
{
	local prp=
	eval prp=\$type_${IFVAR}
	[ "${prp}" = "prp" ] || return 0
	eval prp_slave1=\$prp_slave1_${IFVAR}
	eval prp_slave2=\$prp_slave2_${IFVAR}
	eval prp_supervision=\$prp_supervision_${IFVAR}
	if [ -z "${prp_slave1}" ] || [ -z "${prp_slave2}" ]; then
		eerror "PRP interfaces require two slave interfaces to be set"
		return 1
	fi
	if ! ( IFACE=${prp_slave1} _exists ); then
		eerror "PRP slave1 ${prp_slave1} does not exist"
		return 1
	fi
	if ! ( IFACE=${prp_slave2} _exists ); then
		eerror "PRP slave2 ${prp_slave2} does not exist"
		return 1
	fi

	ebegin "Creating PRP interface ${IFACE}"
	cmd="ip link add name "${IFACE}" type hsr slave1 ${prp_slave1} slave2 ${prp_slave2} ${prp_supervision:+supervision }${prp_supervision} proto 1"
	veinfo $cmd
	if $cmd ; then
		eend 0 && _up && set_interface_type prp
	else
		eend 1
	fi
}


prp_post_stop()
{
	_is_prp || return 0

	ebegin "Removing PRP ${IFACE}"
	cmd="ip link delete "${IFACE}" type prp"
	veinfo "$cmd"
	$cmd
	eend $?
}
