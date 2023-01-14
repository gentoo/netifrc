# Copyright (c) 2016 Emeric Verschuur <emeric@mbedsys.org>
# Copyright (c) 2023 Kerin Millar <kfm@plushkava.net>
# All rights reserved. Released under the 2-clause BSD license.

# Don't complain about local, even though POSIX does not define its behaviour.
# This is unwise but, as things stand, it is being used extensively by netifrc.
# Also, SC2034 and SC2316 are muted because they produce false-positives.
# shellcheck shell=sh disable=SC3043,SC2034,SC2316

l2tp_depend() {
	program ip
	before bridge interface macchanger
}

l2tp_pre_start() {
	local declared_session declared_tunnel l2tpsession l2tptunnel
	local name peer_session_id session_id tunnel_id
	local encap local peer_tunnel_id remote
	local key

	if key="l2tpsession_${IFVAR:?}"; ! eval "[ \${${key}+set} ]"; then
		return
	elif eval "l2tpsession=\$${key}"; _is_blank "${l2tpsession}"; then
		eend 1 "${key} is defined but its value is blank"
	elif ! declared_session=$(_l2tp_parse_opts "${l2tpsession}" "peer_session_id session_id tunnel_id" "name"); then
		eend 1 "${key} is missing at least one required parameter"
	elif eval "${declared_session}"; [ "${name+set}" ]; then
		eend 1 "${key} defines a \"name\" parameter, which is forbidden by netifrc"
	elif ! modprobe l2tp_eth; then
		eend 1 "Couldn't load the l2tp_eth module (perhaps the CONFIG_L2TP_ETH kernel option is disabled)"
	elif key="l2tptunnel_${IFVAR}"; eval "[ \${${key}+set} ]"; then
		if eval "l2tptunnel=\$${key}"; _is_blank "${l2tptunnel}"; then
			eend 1 "${key} is defined but its value is blank"
		elif ! declared_tunnel=$(_l2tp_parse_opts "${l2tptunnel}" "local peer_tunnel_id remote tunnel_id" "encap"); then
			eend 1 "${key} is missing at least one required parameter"
		elif set -- "${tunnel_id}"; eval "${declared_tunnel}"; [ "$1" != "${tunnel_id}" ]; then
			eend 1 "${key} defines a \"tunnel_id\" parameter that contradicts l2tpsession_${IFVAR}"
		elif _l2tp_should_add_tunnel "${tunnel_id}" "${declared_tunnel}"; set -- $?; [ "$1" -eq 2 ]; then
			eend 1 "Tunnel #${tunnel_id} exists but its properties mismatch those defined by ${key}"
		elif [ "$1" -eq 1 ]; then
			# The config matches an existing tunnel.
			true
		elif [ "${encap}" = ip ] && ! modprobe l2tp_ip; then
			eend 1 "Couldn't load the l2tp_ip module (perhaps the CONFIG_L2TP_IP kernel option is disabled)"
		else
			ebegin "Creating L2TPv3 tunnel (tunnel_id ${tunnel_id})"
			printf %s "l2tp add tunnel ${l2tptunnel}" \
			| xargs -E '' ip
			eend $?
		fi
	elif ! _l2tp_has_tunnel "${tunnel_id}"; then
		# A tunnel may incorporate more than one session (link). This
		# module allows for the user not to define a tunnel for a given
		# session. In that case, it will be expected that the required
		# tunnel has already been created to satisfy some other session.
		eend 1 "Tunnel #${tunnel_id} not found (defining ${key} may be required)"
	fi || return

	ebegin "Creating L2TPv3 session (session_id ${session_id} tunnel_id ${tunnel_id})"
	printf %s "l2tp add session ${l2tpsession} name ${IFACE:?}" \
	| xargs -E '' ip && _up
	eend $?
}

l2tp_post_stop() {
	local existing_session session_id tunnel_id

	# This function may be invoked for every interface. If not a virtual
	# interface, it can't possibly be one that's managed by this module, in
	# which case running ip(8) and awk(1) would be a needless expense.
	[ -e /sys/devices/virtual/net/"${IFACE:?}" ] \
	&& existing_session=$(_l2tp_parse_existing_session 2>/dev/null) \
	|| return 0

	eval "${existing_session}"
	set -- session_id "${session_id}" tunnel_id "${tunnel_id}"
	ebegin "Destroying L2TPv3 session ($*)"
	ip l2tp del session "$@"
	eend $? &&
	if ! _l2tp_in_session "${tunnel_id}"; then
		shift 2
		ebegin "Destroying L2TPv3 tunnel ($*)"
		ip l2tp del tunnel "$@"
		eend $?
	fi
}

_is_blank() (
	LC_CTYPE=C
	case $1 in
		*[![:blank:]]*) return 1
	esac
)

_l2tp_parse_opts() {
	# Parses lt2psession or l2tptunnel options using xargs(1), conveying
	# them as arguments to awk(1). The awk program interprets the arguments
	# as a series of key/value pairs and safely prints those specified as
	# being required as variable declarations for evaluation by sh(1).
	# Other keys are handled similarly, only in a way that renders them a
	# no-op. For the program to exit successfully, all key names must be
	# well-formed, all required keys must be seen, and all values must be
	# non-blank. Note that assigning 1 to ARGC prevents awk from treating
	# its arguments as the names of files to be opened.
	printf %s "$1" \
	| LC_CTYPE=C xargs -E '' awk -v q="'" -v required_keys="$2" -v other_keys="$3" '
		function shquote(str) {
			gsub(q, q "\\" q q, str)
			return q str q
		}
		BEGIN {
			argc = ARGC
			ARGC = 1
			gsub(" ", "|", required_keys)
			gsub(" ", "|", other_keys)
			re = "^(" required_keys "|" other_keys ")$"
			sorter = "sort"
			for (i = 1; i < argc; i += 2) {
				key = ARGV[i]
				val = ARGV[i + 1]
				if (key !~ /^[[:alpha:]][_[:alnum:]]+$/) {
					system("ewarn " shquote("Skipping malformed parameter: " key))
				} else if (key ~ re) {
					print key "=" shquote(val) | sorter
					val_by[key] = val
				} else {
					print ": " key "=" shquote(val) | sorter
				}
			}
			close(sorter)
			split(required_keys, keys, "|")
			missing = 0
			for (i in keys) {
				key = keys[i]
				if (! (key in val_by)) {
					system("eerror " shquote("The \"" key "\" parameter is missing"))
					missing += 1
				} else if (val_by[key] ~ /^[[:blank:]]*$/) {
					system("eerror " shquote("The \"" key "\" parameter has a blank value"))
					missing += 1
				}
			}
			exit(!!missing)
		}
	'
}

_l2tp_parse_existing_session() {
	ip l2tp show session \
	| LC_CTYPE=C awk -v iface="${IFACE:?}" '
		BEGIN { found = 0 }
		/^Session [0-9]+ in tunnel [0-9]+$/ {
			session_id = $2
			tunnel_id = $5
		}
		/^[[:blank:]]*interface name:/ && "" $NF == "" iface {
			print "session_id=" session_id
			print "tunnel_id=" tunnel_id
			found = 1
			exit
		}
		END { exit(!found) }
	'
}


_l2tp_parse_existing_tunnel() {
	ip l2tp show tunnel \
	| LC_CTYPE=C awk -v q="'" -v id="$1" '
		function shquote(str) {
			gsub(q, q "\\" q q, str)
			return q str q
		}
		BEGIN {
			found = 0
			sorter = "sort"
		}
		/^Tunnel [0-9]+, encap (IP|UDP)$/ {
			if (found) exit
			tunnel_id = substr($2, 0, length($2) - 1)
			if (tunnel_id == id) {
				found = 1
				print "tunnel_id=" shquote(tunnel_id) | sorter
				print "encap=" shquote(tolower($4)) | sorter
			}
		}
		found && /^[[:blank:]]*From [^[:blank:]]+ to [^[:blank:]]+$/ {
			print "local=" shquote($2) | sorter
			print "remote=" shquote($4) | sorter
		}
		found && /^[[:blank:]]*Peer tunnel [0-9]+$/ {
			print "peer_tunnel_id=" shquote($NF) | sorter
		}
		found && /^[[:blank:]]*UDP source \/ dest ports: [0-9]+\/[0-9]+$/ {
			split($NF, ports, "/")
			print ": udp_sport=" shquote(ports[1]) | sorter
			print ": udp_dport=" shquote(ports[2]) | sorter
		}
		END {
			close(sorter)
			exit(!found)
		}
	'
}

_l2tp_should_add_tunnel() {
	local existing_tunnel

	if ! existing_tunnel=$(_l2tp_parse_existing_tunnel "$1"); then
		return 0
	elif [ "$2" = "${existing_tunnel}" ]; then
		return 1
	else
		return 2
	fi
}

_l2tp_has_tunnel() {
	_l2tp_parse_existing_tunnel "$1" >/dev/null
}

_l2tp_in_session() {
	ip l2tp show session | {
		LC_CTYPE=C
		while read -r line; do
			case ${line} in
				"Session "*" in tunnel $1") return 0
			esac
		done
	}
	return 1
}
