# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

iproute2_depend()
{
	program ip
	provide interface
	after ifconfig
}

# This helper exists for the common pattern of 'veinfo $CMD ; $CMD'
_cmd()
{
	veinfo "${@}"
	"${@}"
}

_up()
{
	_cmd ip link set dev "${IFACE}" up
}

_down()
{
	_cmd ip link set dev "${IFACE}" down
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
	_cmd ip link set dev "${IFACE}" "${flag}" "${opt}"
}

_get_mac_address()
{
	local mac=
	read -r mac < /sys/class/net/"${IFACE}"/address || return 1

	case "${mac}" in
		00:00:00:00:00:00) return 1 ;;
		44:44:44:44:44:44) return 1 ;;
		ff:ff:ff:ff:ff:ff) return 1 ;;
	esac

	printf '%s\n' "${mac}" | LC_ALL=C tr '[:lower:]' '[:upper:]'
}

_set_mac_address()
{
	_cmd ip link set dev "${IFACE}" address "$1"
}

_get_inet_addresses()
{
	local family="$1";
	if [ -z "$family" ]; then
		family="inet"
	fi
	LC_ALL=C ip -family $family addr show "${IFACE}" | \
	sed -n -e 's/.*inet6\? \([^ ]*\).*/\1/p'
}

_get_inet6_addresses() {
	_get_inet_addresses "inet6"
}

_get_inet_address()
{
	set -- $(_get_inet_addresses)
	[ $# = "0" ] && return 1
	echo "$1"
}

_get_inet6_address()
{
	set -- $(_get_inet6_addresses)
	[ $# = "0" ] && return 1
	echo "$1"
}

_add_address()
{
	if [ "$1" = "127.0.0.1/8" -a "${IFACE}" = "lo" ]; then
		_cmd ip addr add "$@" dev "${IFACE}" 2>/dev/null
		return 0
	fi
	local x
	local address netmask broadcast peer anycast label scope
	local valid_lft preferred_lft home nodad
	local confflaglist family raw_address family_maxnetmask
	raw_address="$1" ; shift
	# Extract the netmask on address if present.
	if [ "${raw_address%\/*}" != "${raw_address}" ]; then
		address="${raw_address%\/*}"
		netmask="${raw_address#*\/}"
	else
		address="$raw_address"
	fi

	# Some options are not valid for one family or the other.
	case ${address} in
		*:*) family=6 family_maxnetmask=128 ;;
		*) family=4 family_maxnetmask=32 ;;
	esac

	while [ -n "$*" ]; do
		x=$1 ; shift
		case "$x" in
			netmask|ne*)
				if [ -n "${netmask}" ]; then
					eerror "Too many netmasks: $raw_address netmask $1"
					return 1
				fi
				netmask="$(_netmask2cidr "$1")"
				shift ;;
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
			home|mngtmpaddr|nodad|noprefixroute|h*|mng*|no*)
				case $x in
					h*) x=home ;;
					m*) x=mngtmpaddr ;;
					nop*) x=noprefixroute ;;
					n*) x=nodad ;;
				esac
				# FIXME: If we need to reorder these, this will take more code
				confflaglist="${confflaglist} $x" ; ;;
			*)
				ewarn "Unknown argument to config_$IFACE: $x"
		esac
	done

	# figure out the broadcast address if it is not specified
	# This must NOT be set for IPv6 addresses
	case $family in
		4) [ -z "$broadcast" ] && broadcast="+" ;;
		6) [ -n "$broadcast" ] && eerror "Broadcast keywords are not valid with IPv6 addresses" && return 1 ;;
	esac

	# Always have a netmask
	[ -z "$netmask" ] && netmask=$family_maxnetmask

	# Check for address already existing:
	ip addr show to "${address}/${family_maxnetmask}" dev "${IFACE}" 2>/dev/null | \
		grep -Fsq "${address}"
	address_already_exists=$?

	# This must appear on a single line, continuations cannot be used
	set -- "${address}${netmask:+/}${netmask}" ${peer:+peer} ${peer} ${broadcast:+broadcast} ${broadcast} ${anycast:+anycast} ${anycast} ${label:+label} ${label} ${scope:+scope} ${scope} dev "${IFACE}" ${valid_lft:+valid_lft} $valid_lft ${preferred_lft:+preferred_lft} $preferred_lft $confflaglist
	_cmd ip addr add "$@"
	rc=$?
	# Check return code in some cases
	if [ $rc -ne 0 ]; then
		# If the address already exists, our default behavior is to WARN but continue.
		# You can completely silence this with: errh_IFVAR_address_EEXIST=continue
		if [ $address_already_exists -eq 0 ]; then
			eh_behavior=$(_get_errorhandler_behavior "$IFVAR" "address" "EEXIST" "warn")
			case $eh_behavior in
				continue) msgfunc=true rc=0 ;;
				info) msgfunc=einfo rc=0 ;;
				warn) msgfunc=ewarn rc=0 ;;
				error|fatal) msgfunc=eerror rc=1;;
				*) msgfunc=eerror rc=1 ; eerror "Unknown error behavior: $eh_behavior" ;;
			esac
			eval $msgfunc "Address ${address}${netmask:+/}${netmask} already existed!"
			eval $msgfunc \"$(ip addr show to "${address}/${family_maxnetmask}" dev "${IFACE}" 2>&1)\"
		else
			: # TODO: Handle other errors
		fi
	fi
	return $rc
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

	local cmd= cmd_nometric= have_metric=false
	while [ -n "$1" ]; do
		case "$1" in
			metric) metric=$2 ; cmd="${cmd} metric $2" ; shift ; have_metric=true ;;
			netmask) x="/$(_netmask2cidr "$2")" ; cmd="${cmd}${x}" ; cmd_nometric="${cmd}${x}" ; shift;;
			-host|-net);;
			*) cmd="${cmd} ${1}" ; cmd_nometric="${cmd_nometric} ${1}" ;;
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

	# Check for route already existing:
	ip ${family} route show ${cmd_nometric} dev "${IFACE}" 2>/dev/null | \
		grep -Fsq "${cmd%% *}"
	route_already_exists=$?

	_cmd ip ${family} route append ${cmd} dev "${IFACE}"
	rc=$?
	# Check return code in some cases
	if [ $rc -ne 0 ]; then
		# If the route already exists, our default behavior is to WARN but continue.
		# You can completely silence this with: errh_IFVAR_route_EEXIST=continue
		if [ $route_already_exists -eq 0 ]; then
			eh_behavior=$(_get_errorhandler_behavior "$IFVAR" "route" "EEXIST" "warn")
			case $eh_behavior in
				continue) msgfunc=true rc=0 ;;
				info) msgfunc=einfo rc=0 ;;
				warn) msgfunc=ewarn rc=0 ;;
				error|fatal) msgfunc=eerror rc=1;;
				*) msgfunc=eerror rc=1 ; eerror "Unknown error behavior: $eh_behavior" ;;
			esac
			eval $msgfunc "Route '$cmd_nometric' already existed:"
			eval $msgfunc \"$(ip $family route show ${cmd_nometric} dev "${IFACE}" 2>&1)\"
		else
			: # TODO: Handle other errors
		fi
	fi
	eend $rc
}

_delete_addresses()
{
	_cmd ip addr flush dev "${IFACE}" scope global 2>/dev/null
	_cmd ip addr flush dev "${IFACE}" scope site 2>/dev/null
	if [ "${IFACE}" != "lo" ]; then
		_cmd ip addr flush dev "${IFACE}" scope host 2>/dev/null
	fi
	return 0
}

_has_carrier()
{
	LC_ALL=C ip link show dev "${IFACE}" | grep -Fq "LOWER_UP"
}

# Used by iproute2, ip6rd & ip6to4
_tunnel()
{
	_cmd ip $FAMILY tunnel "$@"
	rc=$?
	# TODO: check return code in some cases
	return $rc
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
		FAMILY="-4" IFACE="${IFACE}" _iproute2_route_flush
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
		FAMILY="-6" IFACE="${IFACE}" _iproute2_route_flush
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
		case $tunnel in
			*mode\ ipip6*) ipproto='-6' ;;
			*mode\ ip6*) ipproto='-6' ;;
			*mode\ any*) ipproto='-6' ;;
		esac

		ebegin "Creating tunnel ${IFVAR}"
		_cmd ip ${ipproto} tunnel add ${tunnel} name "${IFACE}"
		eend $? || return 1
		_up
	fi
	local link=
	eval link=\$iplink_${IFVAR}
	if [ -n "${link}" ]; then
		local ipproto=''
		case $tunnel in
			*mode\ ipip6*) ipproto='-6' ;;
			*mode\ ip6*) ipproto='-6' ;;
			*mode\ any*) ipproto='-6' ;;
		esac

		ebegin "Creating interface ${IFVAR}"
		_cmd ip ${ipproto} link add "${IFACE}" ${link}
		eend $? || return 1
		_up
	fi

	# MTU support
	local mtu=
	eval mtu=\$mtu_${IFVAR}
	if [ -n "${mtu}" ]; then
		_cmd ip link set dev "${IFACE}" mtu "${mtu}"
	fi

	# TX Queue Length support
	local len=
	eval len=\$txqueuelen_${IFVAR}
	if [ -n "${len}" ]; then
		_cmd ip link set dev "${IFACE}" txqueuelen "${len}"
	fi

	local policyroute_order=
	eval policyroute_order=\$policy_rules_before_routes_${IFVAR}
	[ -z "$policyroute_order" ] && policyroute_order=${policy_rules_before_routes:-no}
	yesno "$policyroute_order" && _iproute2_policy_routing

	return 0
}

_iproute2_tunnel_delete() {
	ebegin "Destroying tunnel $1"
	_tunnel del "$1"
	eend $?
}

_iproute2_link_delete() {
	ebegin "Destroying interface $1"
	_cmd ip $FAMILY link del dev "$1"
	eend $?
}

_iproute2_route_flush_supported() {
	case $FAMILY in
		-6) p='/proc/sys/net/ipv6/route/flush' ;;
		-4|*) p='/proc/sys/net/ipv4/route/flush' ;;
	esac
	test -f $p
}

_iproute2_route_flush() {
	if _iproute2_route_flush_supported; then
		_cmd ip $FAMILY route flush table cache dev "${IFACE}"
	fi
}

_iproute2_ipv6_tentative_output() {
	LC_ALL=C ip -family inet6 addr show dev ${IFACE} tentative
}

_iproute2_ipv6_tentative()
{
	[ -n "$(_iproute2_ipv6_tentative_output)" ] && return 0

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

	# This block must be non-fatal, otherwise the interface will not be
	# recorded as starting, and later services may be blocked.
	_iproute2_ipv6_tentative ; ret_tentative=$?
	if [ $ret_tentative -eq 0 -a "$EINFO_VERBOSE" = "yes" ]; then
		veinfo "Found tentative addresses:"
		_iproute2_ipv6_tentative_output
	fi
	# This could be nested, but the conditionals are very deep at that point.
	if [ $ret_tentative -eq 0 -a $_dad_timeout -le 0 ]; then
		einfo "Not waiting for DAD timeout on tentative IPv6 addresses (per conf.d/net dad_timeout)"
	elif [ $ret_tentative -eq 0 ]; then
		einfon "Waiting for tentative IPv6 addresses to complete DAD (${_dad_timeout} seconds) "
		while [ $_dad_timeout -gt 0 ]; do
			_iproute2_ipv6_tentative || break
			sleep 1
			: $(( _dad_timeout -= 1 ))
			printf "."
		done

		echo ""

		if [ $_dad_timeout -le 0 ]; then
			eend 1
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
			FAMILY="-4" IFACE="${IFACE}" _iproute2_route_flush
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
			FAMILY="-6" IFACE="${IFACE}" _iproute2_route_flush
		fi
	fi

	# Don't delete sit0 as it's a special tunnel
	if [ "${IFACE}" != "sit0" ]; then
		if [ -n "$(ip tunnel show "${IFACE}" 2>/dev/null)" ]; then
			_iproute2_tunnel_delete "${IFACE}"
		elif  [ -n "$(ip -6 tunnel show "${IFACE}" 2>/dev/null)" ]; then
			FAMILY=-6 _iproute2_tunnel_delete "${IFACE}"
		fi

		[ -n "$(ip link show "${IFACE}" type gretap 2>/dev/null)" ] && _iproute2_link_delete "${IFACE}"
		[ -n "$(ip link show "${IFACE}" type vxlan 2>/dev/null)" ] && _iproute2_link_delete "${IFACE}"
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
