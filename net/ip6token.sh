# Copyright (c) 2024 Gentoo Authors

ip6token_depend()
{
	program ip
	after interface
}

_config_vars="$_config_vars ip6token"

ip6token_pre_start()
{
	local tconfig
	eval tconfig=\$ip6token_${IFVAR}

	[ -z "${tconfig}" ] && return 0
	ip token set "${tconfig}" dev "${IFACE}"
	return $?
}

ip6token_post_stop()
{
	ip token del dev "${IFACE}"
	return $?
}
