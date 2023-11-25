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

_ip()
{
	veinfo ip "${@}"
	_netns ip "${@}"
}

dummy_pre_start()
{
	local dummy=
	eval dummy="\$type_${IFVAR}"
	[ "${dummy}" = "dummy" ] || return 0

	if ! test -d /sys/module/dummy && ! modprobe dummy; then
		eerror "Couldn't load the dummy module (perhaps the CONFIG_DUMMY kernel option is disabled)"
		return 1
	fi

	if ! _exists ; then
		ebegin "Creating dummy interface ${IFACE}"
		_ip link add name "${IFACE}" type dummy
		eend $?
	fi

	_up && set_interface_type dummy
}


dummy_post_stop()
{
	_is_dummy || return 0

	ebegin "Removing dummy ${IFACE}"
	_ip link delete "${IFACE}" type dummy
	eend $?
}
