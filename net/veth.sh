# Copyright (c) 2018 
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

veth_depend()
{
	program ip
}

_config_vars="$_config_vars veth"


# We need it because _exists() function seeks in /sys/class/net
_netns_exists()
{
	[ -e "/var/run/netns/$1" ]
}


#Creates the network namespace if it doesn't exist. If called with no arguments, does nothing
#Arguments:
# $1 - name of the namespace
_create_ns() {

	vethrc=0
	for _ns in "$@"; do
		if [ -z "$_ns" ]; then
			continue
		fi
		if ! _netns_exists "$_ns"; then
			ip netns add "$_ns" > /dev/null 2>&1
			vethrc=$(($?+ vethrc)) 
		fi	
	done
	return $vethrc
}

#Brings a virtual interface up and takes network namespaces into account
#Arguments: 
# $1 - name of the interface, required!
# $2 - namespace
_bring_peer_up()
{
	if [ ! -z "$2" ]; then
		ip link set "$1" netns "$2" > /dev/null 2>&1
		vethrc=$?
		ip netns exec "$2" ip link set dev "$1" up > /dev/null 2>&1
		vethrc=$(($?+ vethrc)) 
		return $vethrc
	fi

	ip link set dev "$1" up > /dev/null 2>&1
	return $?
} 

#Brings a virtual interface down and takes network namespaces into account
#Arguments: 
# $1 - name of the interface, required!
# $2 - namespace
_bring_peer_down()
{

	if [ ! -z "$2" ]; then
		ip netns exec "$2" ip link del dev "$1" > /dev/null 2>&1
		return $? 
	fi

	ip link del dev "$1" > /dev/null 2>&1
	return $?
}


#Create and bring the veth pair up
_create_peers()
{
	local peer1
	peer1="$(_get_array "veth_${IFVAR}_peer1")"

	local peer2
	peer2="$(_get_array "veth_${IFVAR}_peer2")"

	for x in $peer1 $peer2; do
		if _exists "$x" ; then
			eerror "Interface $x already exists. Can't continue"
			return 1
		fi		
	done

	local netns1
	netns1="$(_get_array "veth_${IFVAR}_ns1")"
	local netns2
	netns2="$(_get_array "veth_${IFVAR}_ns2")"

	local vethrc

	if ! _create_ns "$netns1" "$netns2"
	then
		eerror "Can't create namespaces: $netns1 $netns2"
		return 1
	fi

	ip link add "$peer1" type veth peer name "$peer2" > /dev/null 2>&1 || {
		eerror "Can't create veth peer $peer1 or $peer2"
		return 1
	}


	if ! _bring_peer_up "$peer1" "$netns1"
	then
		eerror "Can't bring the veth peer $peer1 up"
		return 1

	fi
	if ! _bring_peer_up "$peer2" "$netns2"
	then
		eerror "Can't bring the veth peer $peer2 up"
		return 1

	fi

	return 0
}

# Create peers and namespaces
veth_pre_start()
{
	local itype
	eval itype=\$type_${IFVAR}
	if [ "$itype" != "veth" ]; then
		return 0
	fi

	local createveth
	eval createveth=\$veth_${IFVAR}_create
	if [ "$createveth" == "no" ]; then
		return 0
	fi

	type ip >/dev/null 2>&1 || {
		eerror "iproute2 nor found, please install iproute2"
		return 1
	}

	if ! _create_peers
	then
		return 1
	fi


	return 0
}

#Delete the veth pair
#We don't delete namespaces because someone may use them for some purposes
veth_post_stop()
{
	local itype
	eval itype=\$type_${IFVAR}
	if [ "$itype" != "veth" ]; then
		return 0
	fi

	local createveth
	eval createveth=\$veth_${IFVAR}_create
	if [ "$createveth" == "no" ]; then
		return 0
	fi

	local peer1
	peer1="$(_get_array "veth_${IFVAR}_peer1")"

	local netns1
	netns1="$(_get_array "veth_${IFVAR}_ns1")"

	if ! _bring_peer_down "$peer1" "$netns1"
	then
		eerror "Can't delete the veth pair ${IFVAR}"
		eend 1
	fi
	return 0
}
