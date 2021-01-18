# Copyright (c) 2016 Emeric Verschuur <emeric@mbedsys.org>
# All rights reserved. Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

l2tp_depend()
{
	program ip
	before bridge interface macchanger
}

# Extract parameter list to shell vars
#   1. variable prefix
#   2. string to parse
_l2tp_eval_props() {
	local prop_pref=$1
	local prop_list=$2
	eval set -- "$3"
	while [ -n "$1" ]; do
		eval "case $1 in
			$prop_list)
				$prop_pref$1=\"$2\"
				shift
				shift
				;;
			*)
				l2tp_err=\"invalid property $1\"
				return 1
				;;
			
		esac" || return 1
	done
	return 0
}

_is_l2tp() {
	# Check for L2TP support in kernel
	ip l2tp show session 2>/dev/null 1>/dev/null || return 1

	eval "$(ip l2tp show session | \
		awk "match(\$0, /^Session ([0-9]+) in tunnel ([0-9]+)\$/, ret) {sid=ret[1]; tid=ret[2]} 
		match(\$0, /^[ ]*interface name: ${IFACE}\$/) {print \"session_id=\"sid\";tunnel_id=\"tid; exit}")"
	test -n "$session_id"
}

# Get tunnel info
#    1. Output variable prefix
#    2. Tunnel ID to find
_l2tp_get_tunnel_info() {
	local found
	eval "$(ip l2tp show tunnel | \
		awk -v id=$2 -v prefix=$1 '
		match($0, /^Tunnel ([0-9]+), encap (IP|UDP)$/, ret) {
			if (found == "1") exit;
			if (ret[1] == id) {
				print "found=1;"
				print prefix "tunnel_id=" ret[1] ";"
				print prefix "encap=" ret[2] ";";
				found="1"
			}
		} 
		match($0, /^[ ]*From ([^ ]+) to ([^ ]+)$/, ret) {
			if (found == "1") {
				print prefix "local=" ret[1] ";"; 
				print prefix "remote=" ret[2] ";"; 
			}
		}
		match($0, /^[ ]*Peer tunnel ([0-9]+)$/, ret) {
			if (found == "1") {
				print prefix "peer_tunnel_id=" ret[1] ";"; 
			}
		}
		match($0, /^[ ]*UDP source \/ dest ports: ([0-9]+)\/([0-9]+)$/, ret) {
			if (found == "1") {
				print prefix "udp_sport=" ret[1] ";"; 
				print prefix "udp_dport=" ret[2] ";"; 
			}
		}')"
	test -n "$found"
}

_ip_l2tp_add() {
	local e
	e="$(LC_ALL=C ip l2tp add "$@" 2>&1 1>/dev/null)"
	case $e in
		"")
			return 0
			;;
		"RTNETLINK answers: No such process")
			# seems to not be a fatal error but I don't know why I have this error... hmmm
			ewarn "ip l2tp add $2 error: $e"
			return 0
			;;
		*)
			eend 1 "ip l2tp add $2 error: $e"
			return 1
			;;
	esac
	
}

l2tp_pre_start()
{
	local l2tpsession=
	eval l2tpsession=\$l2tpsession_${IFVAR}
	test -n "${l2tpsession}" || return 0
	
	ebegin "Creating L2TPv3 link ${IFVAR}"
	local l2tp_err s_name s_tunnel_id s_session_id s_peer_session_id s_cookie s_peer_cookie s_offset s_peer_offset s_l2spec_type
	if ! _l2tp_eval_props s_ "name|tunnel_id|session_id|peer_session_id|cookie|peer_cookie|offset|peer_offset|l2spec_type" "${l2tpsession}"; then
		eend 1 "l2tpsession_${IFVAR} syntax error: $l2tp_err"
		return 1
	fi
	if [ -n "$s_name" ]; then
		eend 1 "l2tpsession_${IFVAR} error: please remove the \"name\" parameter (this parameter is managed by the system)"
		return 1
	fi
	# Try to load mendatory l2tp_eth kernel module
	if ! modprobe l2tp_eth; then
		eend 1 "l2tp_eth module not present in your kernel (please enable CONFIG_L2TP_ETH option in your kernel config)"
		return 1
	fi
	local l2tptunnel=
	eval l2tptunnel=\$l2tptunnel_${IFVAR}
	if [ -n "${l2tptunnel}" ]; then
		local t_tunnel_id t_encap t_local t_remote t_peer_tunnel_id t_udp_sport t_udp_dport
		_l2tp_eval_props t_ "remote|local|encap|tunnel_id|peer_tunnel_id|encap|udp_sport|udp_dport" "${l2tptunnel}"
		# if encap=ip we need l2tp_ip kernel module
		if [ "${t_encap^^}" = "IP" ] && ! modprobe l2tp_ip; then
			eend 1 "l2tp_ip module not present in your kernel (please enable CONFIG_L2TP_IP option in your kernel config)"
			return 1
		fi
		# Search for an existing tunnel with the same ID
		local f_tunnel_id f_encap f_local f_remote f_peer_tunnel_id f_udp_sport f_udp_dport
		if _l2tp_get_tunnel_info f_ $t_tunnel_id; then
			# check if the existing tunnel has the same property than expected
			if [ "tunnel_id:$f_tunnel_id;encap:$f_encap;local:$f_local;remote:$f_remote;
			peer_tunnel_id:$f_peer_tunnel_id;udp_sport:$f_udp_sport;udp_dport:$f_udp_dport" \
			!= "tunnel_id:$t_tunnel_id;encap:${t_encap^^};local:$t_local;remote:$t_remote;
			peer_tunnel_id:$t_peer_tunnel_id;udp_sport:$t_udp_sport;udp_dport:$t_udp_dport" ]; then
				eend 1 "There are an existing tunnel with id=$s_tunnel_id, but the properties mismatch with the one you want to create"
				return 1
			fi
		else
			veinfo ip l2tp add tunnel ${l2tptunnel}
			_ip_l2tp_add tunnel ${l2tptunnel} || return 1
		fi
	elif ! ip l2tp show tunnel | grep -Eq "^Tunnel $s_tunnel_id,"; then
		# no l2tptunnel_<INTF> declaration, assume that the tunnel is already present
		# checking if tunnel_id exists otherwise raise an error
		eend 1 "Tunnel id=$s_tunnel_id no found (you may have to set l2tptunnel_${IFVAR})"
		return 1
	fi
	veinfo ip l2tp add session ${l2tpsession} name "${IFACE}"
	_ip_l2tp_add session ${l2tpsession} name "${IFACE}" || return 1
	_up
}


l2tp_post_stop()
{
	local session_id tunnel_id
	_is_l2tp || return 0
	
	ebegin "Destroying L2TPv3 link ${IFACE}"
	veinfo ip l2tp del session tunnel_id $tunnel_id session_id $session_id
	ip l2tp del session tunnel_id $tunnel_id session_id $session_id
	if ! ip l2tp show session | grep -Eq "^Session [0-9]+ in tunnel $tunnel_id\$"; then
		#tunnel $tunnel_id no longer used, destoying it...
		veinfo ip l2tp del tunnel tunnel_id $tunnel_id
		ip l2tp del tunnel tunnel_id $tunnel_id
	fi
	eend $?
}
