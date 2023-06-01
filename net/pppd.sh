# Copyright (c) 2005-2023 Gentoo Authors
# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

pppd_depend()
{
	program pppd
	after interface
	before dhcp
	provide ppp
}

is_ppp()
{
	[ -e /run/ppp-"${IFACE}".pid ]
}

requote()
{
	printf "'%s' " "$@"
}

pppd_version_int() {
	# 002004008 is v2.4.8
	printf '%03d' $(pppd --version | awk '/pppd version/ {print $3}' | tr '.' ' ')
}

pppd_is_ge_248()
{
	[ $(pppd_version_int) -ge 002004008 ]
}

pppd_is_ge_250()
{
	[ $(pppd_version_int) -ge 002005000 ]
}

pppd_pidfile()
{
	if pppd_is_ge_250; then
		echo "/run/pppd/ppp-${IFACE}.pid"
	else
		echo "/run/ppp-${IFACE}.pid"
	fi
}

pppd_pre_start()
{
	# Interface has to be called ppp
	[ "${IFACE%%[0-9]*}" = "ppp" ] || return 0

	# Set our base metric
	metric=4000

	if yesno ${IN_BACKGROUND}; then
		local config=
		eval config=\$config_${IFVAR}
		# If no config for ppp then don't default to DHCP
		if [ -z "${config}" ]; then
			eval config_${IFVAR}=null
		fi
		return 0
	fi

	local link= i= unit="${IFACE#ppp}" opts= routemetric=defaultroute-metric

	# https://github.com/paulusmack/ppp/commit/35e5a569c988b1ff865b02a24d9a727a00db4da9
	pppd_is_ge_248 || routemetric=defaultmetric

	# PPP requires a link to communicate over - normally a serial port
	# PPPoE communicates over Ethernet
	# PPPoA communicates over ATM
	# In all cases, the link needs to be available before we start PPP
	eval link=\$link_${IFVAR}
	[ -n "${link}" ] || return 0

	case "${link}" in
		/*)
			if [ ! -e "${link}" ]; then
				eerror "${link} does not exist"
				eerror "Please verify hardware or kernel module (driver)"
				return 1
			fi
			;;
	esac

	if [ -z "${unit}" ]; then
		eerror "PPP requires a unit - use net.ppp[0-9] instead of net.ppp"
		return 1
	fi

	# We need to flatten the useless array
	set -- $(_get_array "pppd_${IFVAR}")
	opts="$@"

	local mtu= hasmtu=false hasmru=false hasmaxfail=false haspersist=false
	local hasupdetach=false hasdefaultmetric=false
	for i in ${opts}; do
		case "${i}" in
			unit|nodetach|linkname)
				eerror "The option \"${i}\" is not allowed in pppd_${IFVAR}"
				return 1
			;;
			defaultmetric) hasdefaultmetric=true;;
			defaultroute-metric) hasdefaultmetric=true;;
			mtu) hasmtu=true;;
			mru) hasmru=true;;
			maxfail) hasmaxfail=true;;
			persist) haspersist=true;;
			updetach) hasupdetach=true;;
		esac
	done

	# Might be set in conf.d/net
	local username= password= passwordset=
	eval username=\$username_${IFVAR}
	eval password=\$password_${IFVAR}
	eval passwordset=\$\{password_${IFVAR}-x\}
	if [ -n "${username}" ] \
	&& [ -n "${password}" -o -z "${passwordset}" ]; then
		opts="plugin passwordfd.so ${opts} passwordfd 0"
	fi

	if ! ${hasdefaultmetric}; then
		local m=
		eval m=\$metric_${IFVAR}
		[ -z "${m}" ] && : $(( m = metric + $(_ifindex) ))
		opts="${opts} ${routemetric} ${m}"
	fi
	if [ -n "${mtu}" ]; then
		${hasmtu} || opts="${opts} mtu ${mtu}"
		${hasmru} || opts="${opts} mru ${mtu}"
	fi
	${hasmaxfail} || opts="${opts} maxfail 0"
	${haspersist} || opts="${opts} persist"

	# Set linkname because we need /run/ppp-${linkname}.pid
	# This pidfile has the advantage of being there,
	# even if ${IFACE} interface was never started
	opts="linkname ${IFACE} ${opts}"

	# Setup auth info
	if [ -n "${username}" ]; then
		opts="user '${username}' remotename ${IFACE} ${opts}"
	fi

	# Load a custom interface configuration file if it exists
	[ -f "/etc/ppp/options.${IFACE}" ] \
		&& opts="${opts} file '/etc/ppp/options.${IFACE}'"

	# Set unit
	opts="unit ${unit} ${opts}"

	# Setup connect script
	local chatprog="chat -e -E -v" phone=
	eval phone=\$phone_number_${IFVAR}
	set -- ${phone}
	[ -n "$1" ] && chatprog="${chatprog} -T '$1'"
	[ -n "$2" ] && chatprog="${chatprog} -U '$2'"
	# We need to flatten the useless array
	set -- $(_get_array "chat_${IFVAR}")
	if [ $# != 0 ]; then
		opts="${opts} connect '$(echo ${chatprog} "$@" | sed -e "s:':'\\\\'':g")'"
	fi

	# Add plugins
	local haspppoa=false haspppoe=false plugins="$(_get_array "plugins_${IFVAR}")"
	local IFS="$__IFS"
	for i in ${plugins}; do
		unset IFS
		set -- ${i}
		case "$1" in
			passwordfd) continue;;
			pppoa) shift; set -- "pppoatm" "$@";;
			capi) shift; set -- "capiplugin" "$@";;
		esac
		case "$1" in
			pppoatm)        haspppoa=true;;
			pppoe|rp-pppoe) haspppoe=true;;
		esac
		if [ "$1" = "pppoe" ] || [ "$1" = "rp-pppoe" ] || [ "$1" = "pppoatm" -a "${link}" != "/dev/null" ]; then
			opts="${opts} connect true"
			set -- "$@" "${link}"
		fi
		opts="plugin $1.so ${opts}"
		shift
		opts="${opts} $@"
	done
	unset IFS

	#Specialized stuff. Insert here actions particular to connection type (pppoe,pppoa,capi)
	local insert_link_in_opts=1
	if ${haspppoe}; then
		if [ ! -e /proc/net/pppoe ]; then
			# Load the PPPoE kernel module
			if ! modprobe pppoe; then
				eerror "kernel does not support PPPoE"
				return 1
			fi
		fi

		# Ensure that the link exists and is up
		( IFACE="${link}"; _exists true && _up ) || return 1
		insert_link_in_opts=0
	fi

	if ${haspppoa}; then
		if [ ! -d /proc/net/atm ]; then
			# Load the PPPoA kernel module
			if ! modprobe pppoatm; then
				eerror "kernel does not support PPPoATM"
				return 1
			fi
		fi

		if [ "${link}" != "/dev/null" ]; then
			insert_link_in_opts=0
		else
			ewarn "WARNING: An [itf.]vpi.vci ATM address was expected in link_${IFVAR}"
		fi

	fi
	[ "${insert_link_in_opts}" = "0" ] || opts="${link} ${opts}"

	local pidfile="$(pppd_pidfile)"

	ebegin "Starting pppd in ${IFACE}"
	mark_service_inactive
	if [ -n "${username}" ] \
	&& [ -n "${password}" -o -z "${passwordset}" ]; then
		printf "%s" "${password}" | \
		eval start-stop-daemon --start --exec pppd \
			--pidfile "${pidfile}" -- "${opts}" >/dev/null
	else
		eval start-stop-daemon --start --exec pppd \
			--pidfile "${pidfile}" -- "${opts}" >/dev/null
	fi

	if ! eend $? "Failed to start PPP"; then
		mark_service_stopped
		return 1
	fi

	if ${hasupdetach}; then
		_show_address
	else
		einfo "Backgrounding ..."
	fi

	# pppd will re-call us when we bring the interface up
	exit 0
}

# Dummy function for users that still have config_ppp0="ppp"
pppd_start()
{
	return 0
}

pppd_stop()
{
	yesno ${IN_BACKGROUND} && return 0

	local pidfile="$(pppd_pidfile)"
	if [ ! -s "${pidfile}" ]; then
		# Try the old path.
		pidfile="/run/ppp-${IFACE}.pid"
		[ -s "${pidfile}" ] || return 0
	fi

	# Give pppd at least 30 seconds do die, #147490
	einfo "Stopping pppd on ${IFACE}"
	start-stop-daemon --stop --quiet --exec pppd \
		--pidfile "${pidfile}" --retry 30
	eend $?
}
