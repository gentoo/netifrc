# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

macchanger_depend()
{
	before macnet
	# no program 'macchanger', as we have partial functionality without it
}

_config_vars="$_config_vars mac"

macchanger_pre_start()
{
	# We don't change MAC addresses from background
	yesno ${IN_BACKGROUND} && return 0

	local mac= opts= try= output= rc=

	eval mac=\$mac_${IFVAR}
	[ -z "${mac}" ] && return 0

	_exists true || return 1

	ebegin "Changing MAC address of ${IFACE}"

	# The interface needs to be up for macchanger to work most of the time
	_down

	mac=$(echo "${mac}" | tr '[:upper:]' '[:lower:]')
	local hex="[0-9a-f][0-9a-f]"
	case "${mac}" in
		# specific mac-addr
		${hex}:${hex}:${hex}:${hex}:${hex}:${hex})
			# We don't need macchanger to change to a specific
			# mac address
			_set_mac_address "${mac}"
			if eend "$?"; then
				mac=$(_get_mac_address)
				eindent
				einfo "changed to ${mac}"
				eoutdent
				_up
				return 0
			fi
			;;

		# increment MAC address, default macchanger behavior
		increment) opts="${opts}";;

		# randomize just the ending bytes
		random-ending) opts="${opts} -e";;

		# keep the same kind of physical layer (eg fibre, copper)
		random-samekind) opts="${opts} -a";;

		# randomize to any known vendor of any physical layer type
		random-anykind) opts="${opts} -A";;

		# fully random bytes
		random-full|random) opts="${opts} -r";;

		# default case is just to pass on all the options
		*) opts="${opts} -m ${mac}";;
	esac

	if [ ! -x /sbin/macchanger ]; then
		eerror "For changing MAC addresses, emerge net-analyzer/macchanger"
		return 1
	fi

	for try in 1 2; do
		# Sometimes the interface needs to be up
		[ "${try}" -eq 2 ] && _up
		output=$(/sbin/macchanger ${opts} "${IFACE}")
		rc=$?
		[ "${rc}" -eq 0 ] && break
	done

	if [ "${rc}" -ne 0 ]; then
		eerror "${output}"
		eend 1 "Failed to set MAC address"
		return 1
	fi

	eend 0
	eindent
	newmac=$(_get_mac_address)
	einfo "changed to ${newmac}"
	eoutdent

	return 0
}
