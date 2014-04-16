# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.

iproute2_depend()
{
	program ip
	provide interface
	after ifconfig
}

_up()
{
	veinfo ip link set dev "${IFACE}" up
	ip link set dev "${IFACE}" up
}

_down()
{
	veinfo ip link set dev "${IFACE}" down
	ip link set dev "${IFACE}" down
}

_exists()
{
	[ -e /sys/class/net/"$IFACE" ]
}

_ifindex()
{
	local index=-1
	local f v
	if [ -e /sys/class/net/"${IFACE}"/ifindex ]; then
		index=$(cat /sys/class/net/"${IFACE}"/ifindex)
	else
		for f in /sys/class/net/*/ifindex ; do
			v=$(cat $f)
			[ $v -gt $index ] && index=$v
		done
		: $(( index += 1 ))
	fi
	echo "${index}"
	return 0
}

_is_wireless()
{
	# Support new sysfs layout
	[ -d /sys/class/net/"${IFACE}"/wireless -o \
		-d /sys/class/net/"${IFACE}"/phy80211 ] && return 0

	[ ! -e /proc/net/wireless ] && return 1
	grep -Eq "^[[:space:]]*${IFACE}:" /proc/net/wireless
}

_set_flag()
{
	local flag=$1 opt="on"
	if [ "${flag#-}" != "${flag}" ]; then
		flag=${flag#-}
		opt="off"
	fi
	veinfo ip link set dev "${IFACE}" "${flag}" "${opt}"
	ip link set dev "${IFACE}" "${flag}" "${opt}"
}

_get_mac_address()
{
	local mac=$(LC_ALL=C ip link show "${IFACE}" | sed -n \
		-e 'y/abcdef/ABCDEF/' \
		-e '/link\// s/^.*\<\(..:..:..:..:..:..\)\>.*/\1/p')

	case "${mac}" in
		00:00:00:00:00:00);;
		44:44:44:44:44:44);;
		FF:FF:FF:FF:FF:FF);;
		"");;
		*) echo "${mac}"; return 0;;
	esac

	return 1
}

_set_mac_address()
{
	veinfo ip link set dev "${IFACE}" address "$1"
	ip link set dev "${IFACE}" address "$1"
}

_get_inet_addresses()
{
	LC_ALL=C ip -family inet addr show "${IFACE}" | \
	sed -n -e 's/.*inet \([^ ]*\).*/\1/p'
}

_get_inet_address()
{
	set -- $(_get_inet_addresses)
	[ $# = "0" ] && return 1
	echo "$1"
}

_add_address()
{
	if [ "$1" = "127.0.0.1/8" -a "${IFACE}" = "lo" ]; then
		veinfo ip addr add "$@" dev "${IFACE}" 2>/dev/null
		ip addr add "$@" dev "${IFACE}" 2>/dev/null
		return 0
	fi
	local x
	local address netmask broadcast peer anycast label scope
	local valid_lft preferred_lft home nodad
	local confflaglist
	address="$1" ; shift
	while [ -n "$*" ]; do
		x=$1 ; shift
		case "$x" in
			netmask|ne*)
				netmask="/$(_netmask2cidr "$1")" ; shift ;;
			broadcast|brd|br*)
				broadcast="$1" ; shift ;;
			pointopoint|pointtopoint|peer|po*|pe*)
				peer="$1" ; shift ;;
			anycast|label|scope|valid_lft|preferred_lft|a*|l*|s*|v*|pr*)
				case $x in
					a*) x=anycast ;;
					l*) x=label ;;
					s*) x=scope ;;
					v*) x=valid_lft ;;
					pr*) x=preferred_lft ;;
				esac
				eval "$x=$1" ; shift ;;
			home|nodad|h*|no*)
				case $x in h*) x=home ;; n*) x=nodad ;; esac
				# FIXME: If we need to reorder these, this will take more code
				confflaglist="${confflaglist} $x" ; ;;
			*)
				ewarn "Unknown argument to config_$IFACE: $x"
		esac
	done

	# Always scope lo addresses as host unless specified otherwise
	if [ "${IFACE}" = "lo" ]; then
		[ -z "$scope" ] && scope="host"
	fi

	# figure out the broadcast address if it is not specified
	# This must NOT be set for IPv6 addresses
	if [ "${address#*:}" = "${address}" ]; then
		[ -z "$broadcast" ] && broadcast="+"
	elif [ -n "$broadcast" ]; then
		eerror "Broadcast keywords are not valid with IPv6 addresses"
		return 1
	fi

	# This must appear on a single line, continuations cannot be used
	set -- "${address}${netmask}" ${peer:+peer} ${peer} ${broadcast:+broadcast} ${broadcast} ${anycast:+anycast} ${anycast} ${label:+label} ${label} ${scope:+scope} ${scope} dev "${IFACE}" ${valid_lft:+valid_lft} $valid_lft ${preferred_lft:+preferred_lft} $preferred_lft $confflaglist
	veinfo ip addr add "$@"
	ip addr add "$@"
}

_add_route()
{
	local family=

	if [ "$1" = "-A" -o "$1" = "-f" -o "$1" = "-family" ]; then
		family="-f $2"
		shift; shift
	elif [ "$1" = "-4" ]; then
	    family="-f inet"
		shift
	elif [ "$1" = "-6" ]; then
	    family="-f inet6"
		shift
	fi

	if [ $# -eq 3 ]; then
		set -- "$1" "$2" via "$3"
	elif [ "$3" = "gw" ]; then
		local one=$1 two=$2
		shift; shift; shift
		set -- "${one}" "${two}" via "$@"
	fi

	local cmd= have_metric=false
	while [ -n "$1" ]; do
		case "$1" in
			metric) cmd="${cmd} $1"; have_metric=true;;
			netmask) cmd="${cmd}/$(_netmask2cidr "$2")"; shift;;
			-host|-net);;
			*) cmd="${cmd} $1";;
		esac
		shift
	done

	# We cannot use a metric if we're using a nexthop
	if ! ${have_metric} && \
		[ -n "${metric}" -a \
			"${cmd##* nexthop }" = "$cmd" ]
	then
		cmd="${cmd} metric ${metric}"
	fi

	veinfo ip ${family} route append ${cmd} dev "${IFACE}"
	ip ${family} route append ${cmd} dev "${IFACE}"
	eend $?
}

_delete_addresses()
{
	veinfo ip addr flush dev "${IFACE}" scope global 2>/dev/null
	ip addr flush dev "${IFACE}" scope global 2>/dev/null
	veinfo ip addr flush dev "${IFACE}" scope site 2>/dev/null
	ip addr flush dev "${IFACE}" scope site 2>/dev/null
	if [ "${IFACE}" != "lo" ]; then
		veinfo ip addr flush dev "${IFACE}" scope host 2>/dev/null
		ip addr flush dev "${IFACE}" scope host 2>/dev/null
	fi
	return 0
}

_has_carrier()
{
	LC_ALL=C ip link show dev "${IFACE}" | grep -q "LOWER_UP"
}

_tunnel()
{
	veinfo ip tunnel "$@"
	ip tunnel "$@"
}

# This is just to trim whitespace, do not add any quoting!
_trim() {
	echo $*
}

# This is our interface to Routing Policy Database RPDB
# This allows for advanced routing tricks
_ip_rule_runner() {
	local cmd rules OIFS="${IFS}" family
	if [ "$1" = "-4" -o "$1" = "-6" ]; then
		family="$1"
		shift
	else
		family="-4"
	fi
	cmd="$1"
	rules="$2"
	veindent
	local IFS="$__IFS"
	for ru in $rules ; do
		unset IFS
		ruN="$(_trim "${ru}")"
		[ -z "${ruN}" ] && continue
		vebegin "${cmd} ${ruN}"
		ip $family rule ${cmd} ${ru}
		veend $?
		local IFS="$__IFS"
	done
	IFS="${OIFS}"
	veoutdent
}

_iproute2_policy_routing()
{
	# Kernel may not have IP built in
	if [ -e /proc/net/route ]; then
		local rules="$(_get_array "rules_${IFVAR}")"
		if [ -n "${rules}" ]; then
			if ! ip -4 rule list | grep -q "^"; then
				eerror "IP Policy Routing (CONFIG_IP_MULTIPLE_TABLES) needed for ip rule"
			else
				service_set_value "ip_rule" "${rules}"
				einfo "Adding IPv4 RPDB rules"
				_ip_rule_runner -4 add "${rules}"
			fi
		fi
		veinfo ip -4 route flush table cache dev "${IFACE}"
		ip -4 route flush table cache dev "${IFACE}"
	fi

	# Kernel may not have IPv6 built in
	if [ -e /proc/net/ipv6_route ]; then
		local rules="$(_get_array "rules6_${IFVAR}")"
		if [ -n "${rules}" ]; then
			if ! ip -6 rule list | grep -q "^"; then
				eerror "IPv6 Policy Routing (CONFIG_IPV6_MULTIPLE_TABLES) needed for ip rule"
			else
				service_set_value "ip6_rule" "${rules}"
				einfo "Adding IPv6 RPDB rules"
				_ip_rule_runner -6 add "${rules}"
			fi
		fi
		veinfo ip -6 route flush table cache dev "${IFACE}"
		ip -6 route flush table cache dev "${IFACE}"
	fi
}

iproute2_pre_start()
{
	local tunnel=
	eval tunnel=\$iptunnel_${IFVAR}
	if [ -n "${tunnel}" ]; then
		# Set our base metric to 1000
		metric=1000
		# Bug#347657: If the mode is ipip6, ip6ip6, ip6gre or any, the -6 must
		# be passed to iproute2 during tunnel creation.
		# state 'any' does not exist for IPv4
		local ipproto=''
		[ "${tunnel##mode ipip6}" != "${tunnel}" ] && ipproto='-6'
		[ "${tunnel##mode ip6ip6}" != "${tunnel}" ] && ipproto='-6'
		[ "${tunnel##mode ip6gre}" != "${tunnel}" ] && ipproto='-6'
		[ "${tunnel##mode any}" != "${tunnel}" ] && ipproto='-6'

		ebegin "Creating tunnel ${IFVAR}"
		veinfo ip ${ipproto} tunnel add ${tunnel} name "${IFACE}"
		ip ${ipproto} tunnel add ${tunnel} name "${IFACE}"
		eend $? || return 1
		_up
	fi

	# MTU support
	local mtu=
	eval mtu=\$mtu_${IFVAR}
	if [ -n "${mtu}" ]; then
		veinfo ip link set dev "${IFACE}" mtu "${mtu}"
		ip link set dev "${IFACE}" mtu "${mtu}"
	fi

	# TX Queue Length support
	local len=
	eval len=\$txqueuelen_${IFVAR}
	if [ -n "${len}" ]; then
		veinfo ip link set dev "${IFACE}" txqueuelen "${len}"
		ip link set dev "${IFACE}" txqueuelen "${len}"
	fi

	local policyroute_order=
	eval policyroute_order=\$policy_rules_before_routes_${IFVAR}
	[ -z "$policyroute_order" ] && policyroute_order=${policy_rules_before_routes:-no}
	yesno "$policyroute_order" && _iproute2_policy_routing

	return 0
}

_iproute2_ipv6_tentative()
{
	[ -n "$(LC_ALL=C ip -family inet6 addr show dev ${IFACE} tentative)" ] && return 0

	return 1
}

iproute2_post_start()
{
	local _dad_timeout=

	eval _dad_timeout=\$dad_timeout_${IFVAR}
	_dad_timeout=${_dad_timeout:-${dad_timeout:-5}}

	local policyroute_order=
	eval policyroute_order=\$policy_rules_before_routes_${IFVAR}
	[ -z "$policyroute_order" ] && policyroute_order=${policy_rules_before_routes:-no}
	yesno "$policyroute_order" || _iproute2_policy_routing

	if _iproute2_ipv6_tentative; then
		einfon "Waiting for IPv6 addresses (${_dad_timeout} seconds) "
		while [ $_dad_timeout -gt 0 ]; do
			_iproute2_ipv6_tentative || break
			sleep 1
			: $(( _dad_timeout -= 1 ))
			printf "."
		done

		echo ""

		if [ $_dad_timeout -le 0 ]; then
			eend 1
			return 1
		else
			eend 0
		fi
	fi

	return 0
}

iproute2_post_stop()
{
	# Kernel may not have IP built in
	if [ -e /proc/net/route ]; then
		local rules="$(service_get_value "ip_rule")"
		if [ -n "${rules}" ]; then
			einfo "Removing IPv4 RPDB rules"
			_ip_rule_runner -4 del "${rules}"
		fi

		# Only do something if the interface actually exist
		if _exists; then
			veinfo ip -4 route flush table cache dev "${IFACE}"
			ip -4 route flush table cache dev "${IFACE}"
		fi
	fi

	# Kernel may not have IPv6 built in
	if [ -e /proc/net/ipv6_route ]; then
		local rules="$(service_get_value "ip6_rule")"
		if [ -n "${rules}" ]; then
			einfo "Removing IPv6 RPDB rules"
			_ip_rule_runner -6 del "${rules}"
		fi

		# Only do something if the interface actually exist
		if _exists; then
			veinfo ip -6 route flush table cache dev "${IFACE}"
			ip -6 route flush table cache dev "${IFACE}"
		fi
	fi

	# Don't delete sit0 as it's a special tunnel
	if [ "${IFACE}" != "sit0" ]; then
		if [ -n "$(ip tunnel show "${IFACE}" 2>/dev/null)" ]; then
			ebegin "Destroying tunnel ${IFACE}"
			veinfo ip tunnel del "${IFACE}"
			ip tunnel del "${IFACE}"
			eend $?
		fi
	fi
}

# Is the interface administratively/operationally up?
# The 'UP' status in ifconfig/iproute2 is the administrative status
# Operational state is available in iproute2 output as 'state UP', or the
# operstate sysfs variable.
# 0: up
# 1: down
# 2: invalid arguments
is_admin_up()
{
	local iface="$1"
	[ -z "$iface" ] && iface="$IFACE"
	ip link show dev $iface | \
	sed -n '1,1{ /[<,]UP[,>]/{ q 0 }}; q 1; '
}

is_oper_up()
{
	local iface="$1"
	[ -z "$iface" ] && iface="$IFACE"
	read state </sys/class/net/"${iface}"/operstate
	[ "x$state" = "up" ]
}
