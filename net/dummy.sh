# Copyright (c) 2015 Gentoo Foundation
# All rights reserved. Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

dummy_depend()
{
	program ip
	after interface
	before dhcp macchanger
}

_is_dummy() {
	is_interface_type dummy
}

dummy_pre_start()
{
	local dummy=
	eval dummy=\$type_${IFVAR}
	[ "${dummy}" = "dummy" ] || return 0

	ebegin "Creating dummy interface ${IFACE}"
	cmd="ip link add name "${IFACE}" type dummy"
	veinfo $cmd
	if $cmd ; then
		eend 0 && _up && set_interface_type dummy
	else
		eend 1
	fi
}


dummy_post_stop()
{
	_is_dummy || return 0

	ebegin "Removing dummy ${IFACE}"
	cmd="ip link delete "${IFACE}" type dummy"
	veinfo "$cmd"
	$cmd
	eend $?
}
