# Copyright (c) 2016 Brian Evans <grknight@gentoo.org>
# Based on iwconfig.sh Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

_config_vars="$_config_vars ssid mode associate_timeout sleep_scan"
_config_vars="$_config_vars preferred_aps blacklist_aps"
_config_vars="$_config_vars mesh"

iw_depend()
{
	program /usr/sbin/iw
	after plug
	before interface
	provide wireless
	# Prefer us over iwconfig
	after iwconfig
}

_get_ssid()
{
	local i=5 ssid=

	while [ ${i} -gt 0 ]; do
		ssid=$(iw dev "${IFACE}" link \
			| sed -n -e 's/^.*SSID: \(.*[^ ]\).*/\1/p')
		if [ -n "${ssid}" ]; then
			echo "${ssid}"
			return 0
		fi
		sleep 1
		: $(( i -= 1 ))
	done

	return 1
}

_get_ap_mac_address()
{
	local mac="$(iw dev "${IFACE}" station dump \
			| sed -n -e 's/^Station \([0-9a-f:]*\).*/\1/p')"
	case "${mac}" in
		"00:00:00:00:00:00") return 1;;
		"44:44:44:44:44:44") return 1;;
		"FF:00:00:00:00:00") return 1;;
		"FF:FF:FF:FF:FF:FF") return 1;;
		*) echo "${mac}";;
	esac
}

iw_get_mode()
{
	LC_ALL=C iw dev "${IFACE}" info | \
	sed -n -e 's/^.*type \(.*[^ ]\).*/\1/p' | \
	tr '[:upper:]' '[:lower:]'
}

iw_get_channel()
{
	LC_ALL=C iw dev "${IFACE}" info | \
	sed -n -e 's/^.*channel \(.*\)/\1/p' | cut -d , -f 1 |\
	tr '[:upper:]' '[:lower:]'
}

iw_set_mode()
{
	local mode="$1"
	[ "${mode}" = "$(iw_get_mode)" ] && return 0

	# Devicescape stack requires the interface to be down
	_down
	iw dev "${IFACE}" set type "${mode}" || return 1
	_up
}

iw_get_type()
{
	LC_ALL=C iw dev "${IFACE}" info | \
	sed -n -e 's/^'"$1"' *\([^ ]* [^ ]*\).*/\1/p'
}

iw_report()
{
	local mac= m="connected to"
	local ssid="$(_get_ssid)"
	local wep_status="(WEP DISABLED)"
	local key="$(iw_get_wep_key)"
	if [ -n "${key}" -a "${key}" != "off" ] ; then
		wep_status="(WEP ENABLED)"
	fi
	local channel="$(iw_get_channel)"
	[ -n "${channel}" ] && channel="on channel ${channel} "
	local mode="$(iw_get_mode)"
	mac="$(_get_ap_mac_address)"
	[ -n "${mac}" ] && mac=" at ${mac}"

	eindent
	einfo "${IFACE} ${m} SSID \"${SSID}\"${mac}"
	einfo "in ${mode} mode ${channel}${wep_status}"
	eoutdent
}

iw_get_wep_key()
{
	local mac="$1" key= format_key=
	[ -n "${mac}" ] && mac="$(echo "${mac}" | sed -e 's/://g')"
	eval key=\$mac_key_${mac}
	[ -z "${key}" ] && eval key=\$key_${SSIDVAR}
	if [ -z "${key}" ]; then
		echo "off"
	else
		format_key=${key#s:}
		if [ "${key}" = "${format_key}" ] ; then
			# Hex key since it does not start with s:
			key="d:0:${format_key}"
		else
			key="0:${format_key}"
		fi
		set -- ${key}
		echo "${key}"
	fi
}

iw_user_config()
{
	local conf= var=${SSIDVAR} config=
	[ -z "${var}" ] && var=${IFVAR}

	config="$(_get_array "iw_${var}")"
	local IFS="$__IFS"
	for conf in ${config}; do
		unset IFS
		if ! eval iw dev "${IFACE}" "${conf}"; then
			ewarn "${IFACE} does not support the following configuration commands"
			ewarn "  ${conf}"
		fi
	done
	unset IFS
}

iw_setup_adhoc()
{
	local mode="$1" channel=
	if [ -z "${SSID}" ]; then
		eerror "${IFACE} requires an SSID to be set to operate in ${mode} mode"
		eerror "adjust the ssid_${IFVAR} setting in /etc/conf.d/net"
		return 1
	fi
	SSIDVAR=$(shell_var "${SSID}")
	local key=$(iw_get_wep_key)

	iw_set_mode "ibss"

	eval channel=\$channel_${SSIDVAR}
	[ -z "${channel}" ] && eval channel=\$channel_${IFVAR}
	# Convert channel numbers into MHz for iw
	# 5MHz increments starting with 2412MHz
	# We default the channel to 3 (2422MHz)
	channel=$(expr \( \( "${channel:-3}" - 1 \) \* 5 \) \+ 2412)
	if [ -z "${key}" -o "${key}" = "off" ]; then
		iw dev "${IFACE}" ibss join "${SSID}" "${channel}" || return 1
	else
		iw dev "${IFACE}" ibss join "${SSID}" "${channel}" \
			key "${key}"|| return 1
	fi

	# Finally apply the user Config
	iw_user_config

	iw_report
	return 0
}

iw_setup_mesh()
{
	if [ -z "${MESH}" ]; then
		eerror "${IFACE} requires a MESH to be set to operate in mesh mode"
		eerror "adjust the mesh_${IFVAR} setting in /etc/conf.d/net"
		return 1
	fi

	iw_set_mode 'mesh'

	veinfo "Joining mesh '$MESH' with $IFACE"
	iw ${IFACE} mesh join "${MESH}" || return 1

	# Finally apply the user Config
	iw_user_config

	iw_report
	return 0
}

iw_wait_for_association()
{
	local timeout= i=0
	eval timeout=\$associate_timeout_${IFVAR}
	timeout=${timeout:-10}

	[ ${timeout} -eq 0 ] \
		&& vewarn "WARNING: infinite timeout set for association on ${IFACE}"

	while true; do
		# Use sysfs if we can
		if [ -e /sys/class/net/"${IFACE}"/carrier ]; then
			if [ "$(cat /sys/class/net/"${IFACE}"/carrier)" = "1" ]; then
				local station_mac=$(iw dev "${IFACE}" station dump \
					| sed -n -e 's/^Station \([0-9a-f:]*\).*/\1/p')
				# Double check we have an ssid and a non-zero
				# mac address.  This is mainly for buggy
				# prism54 drivers that always set their
				# carrier on or buggy madwifi drivers that
				# sometimes have carrier on and ssid set
				# without being associated.  :/
				[ -n "$(iw dev "${IFACE}" info | grep -F ssid)" ] && [ "${station_mac}" != "00:00:00:00:00:00" ] && return 0
			fi
		else
			local atest=
			eval atest=\$associate_test_${IFVAR}
			atest=${atest:-mac}
			if [ "${atest}" = "mac" -o "${atest}" = "all" ]; then
				[ -n "$(_get_ap_mac_address)" ] && return 0
			fi
			if [ "${atest}" = "quality" -o "${atest}" = "all" ]; then
				[ "$(sed -n -e 's/^.*'"${IFACE}"': *[0-9]* *\([0-9]*\).*/\1/p' \
					/proc/net/wireless)" != "0" ] && return 0
			fi
		fi

		sleep 1
		[ ${timeout} -eq 0 ] && continue
		: $(( i +=  1 ))
		[ ${i} -ge ${timeout} ] && return 1
	done
	return 1
}

iw_associate()
{
	local mode="${1:-managed}" mac="$2" wep_required="$3"
	local freq="$4" chan="$5"
	local w="(WEP Disabled)" key=

	if [ "${wep_required}" = "WPA" ]; then
		ewarn "\"${SSID}\" uses WPA, please use wpa_supplicant for this SSID"
		return 1
	fi

	iw_set_mode "${mode}"

	SSIDVAR=$(shell_var "${SSID}")
	key="$(iw_get_wep_key "${mac}")"
	[ -z "${key}" ] && key=off
	if [ "${wep_required}" = "on" -a "${key}" = "off" ]; then
		ewarn "WEP key is not set for \"${SSID}\""
		return 1
	fi
	if [ "${wep_required}" = "off" -a "${key}" != "off" ]; then
		key="off"
		ewarn "\"${SSID}\" is not WEP enabled"
	fi

	if [ -n "${key}" -a "${key}" != "off" ]; then
		if ! iw dev "${IFACE}" connect "${SSID}" keys "${key}" ; then
			ewarn "${IFACE} does not support setting keys"
			ewarn "or the parameter \"mac_key_${SSIDVAR}\" or \"key_${SSIDVAR}\" is incorrect"
			return 1
		fi
		w="(WEP Enabled)"
	fi
	if ! iw dev "${IFACE}" connect "${SSID}" ; then
		ewarn "${IFACE} does not support setting SSID to \"${SSID}\""
	fi

	# Only use channel or frequency
	if [ -n "${chan}" ]; then
		iw dev "${IFACE}" set channel "${chan}"
	elif [ -n "${freq}" ]; then
		iw dev "${IFACE}" set freq "${freq}"
	fi

	# Finally apply the user Config
	iw_user_config

	ebegin "Connecting to \"${SSID}\" in ${mode} mode ${w}"

	if type preassociate >/dev/null 2>&1; then
		veinfo "Running preassociate function"
		veindent
		( preassociate )
		local e=$?
		veoutdent
		if [ ${e} -eq 0 ]; then
			veend 1 "preassociate \"${SSID}\" on ${IFACE} failed"
			return 1
		fi
	fi

	if ! iw_wait_for_association; then
		eend 1
		return 1
	fi
	eend 0

	iw_report

	if type postassociate >/dev/null 2>&1; then
		veinfo "Running postassociate function"
		veindent
		( postassociate )
		veoutdent
	fi

	return 0
}

iw_scan()
{
	local x= i=0 scan=
	einfo "Scanning for access points"
	eindent

	# Sleep if required
	eval x=\$sleep_scan_${IFVAR}
	[ -n "${x}" ] && sleep "${x}"

	while [ ${i} -lt 3 ]; do
	    local scan="${scan}${scan:+ }$(LC_ALL=C iw dev "${IFACE}" scan 2>/dev/null | sed -e "s/'/'\\\\''/g" -e "s/$/'/g" -e "s/^/'/g")"
		# If this is the first pass and txpower as off and we have no
		# results then we need to wait for at least 2 seconds whilst
		# the interface does an initial scan.
		if [ "${i}" = "0" -a "${txpowerwasoff}" = "0" ]; then
			case "${scan}" in
				"'${IFACE} "*"No scan results"*)
					sleep 2
					txpowerwasoff=1
					continue
					;;
			esac
		fi
	    : $(( i += 1 ))
	done

	if [ -z "${scan}" ]; then
		ewarn "${IFACE} does not support scanning"
		eoutdent
		eval x=\$adhoc_ssid_${IFVAR}
		[ -n "${x}" ] && return 0
		if [ -n "${preferred_aps}" ]; then
			[ "${associate_order}" = "forcepreferred" ] || \
			[ "${associate_order}" = "forcepreferredonly" ] && return 0
		fi
		eerror "You either need to set a preferred_aps list in /etc/conf.d/net"
		eerror "   preferred_aps=\"SSID1 SSID2\""
		eerror "   and set associate_order_${IFVAR}=\"forcepreferred\""
		eerror "   or set associate_order_${IFVAR}=\"forcepreferredonly\""
		eerror "or hardcode the  SSID to \"any\" and let the driver find an Access Point"
		eerror "   ssid_${IFVAR}=\"any\""
		eerror "or configure defaulting to Ad-Hoc when Managed fails"
		eerror "   adhoc_ssid_${IFVAR}=\"WLAN\""
		eerror "or hardcode the SSID against the interface (not recommended)"
		eerror "   ssid_${IFVAR}=\"SSID\""
		return 1
	fi

	APS=-1
	eval set -- ${scan}
	for line; do
		case "${line}" in
			BSS*)
				x="${line#* }"
				: $(( APS += 1 ))
				eval MAC_${APS}="\""$(echo "${x%(*}" | tr '[:lower:]' '[:upper:]')"\""
				eval QUALITY_${APS}=0
				;;
			*SSID:*)
				x=${line#*: }
				eval SSID_${APS}=\$x
				;;
			*Mode:*)
				x="$(echo "${line#*:}" | tr '[:upper:]' '[:lower:]')"
				if [ "${x}" = "master" ]; then
					eval MODE_${APS}=managed
				else
					eval MODE_${APS}=\$x
				fi
				;;
			*WEP*)
				eval ENC_${APS}=on
				;;
			*WPA*)
				eval ENC_${APS}=WPA
				;;
			*"DS Parameter set: channel"*)
				x=${line#*: channel}
				x=${x%% *}
				eval CHAN_${APS}=\$x
				;;
			*signal*)
				x=${line#*:}
				x=${x%/*}
				x="$(echo "${x}" | sed -e 's/[^[:digit:]]//g')"
				x=${x:-0}
				eval QUALITY_${APS}=\$x
				;;
		esac
	done

	if [ -z "${MAC_0}" ]; then
		ewarn "no access points found"
		eoutdent
		return 1
	fi

	# Sort based on quality
	local i=0 k=1 a= b= x= t=
	while [ ${i} -lt ${APS} ]; do
	    : $(( k = i + 1 ))
	    while [ ${k} -le ${APS} ]; do
		eval a=\$QUALITY_${i}
		[ -z "${a}" ] && break
		eval b=\$QUALITY_${k}
		# Lower values are better signal
		if [ -n "${b}" -a "${a}" -gt "${b}" ]; then
		    for x in MAC SSID MODE CHAN QUALITY ENC; do
			eval t=\$${x}_${i}
			eval ${x}_${i}=\$${x}_${k}
			eval ${x}_${k}=\$t
		    done
		fi
		: $(( k += 1 ))
	    done
	    : $(( i += 1 ))
	done

	# Strip any duplicates
	local i=0 k=1 a= b=
	while [ ${i} -lt ${APS} ]; do
		: $(( k = i + 1 ))
		while [ ${k} -le ${APS} ]; do
			eval a=\$MAC_${i}
			eval b=\$MAC_${k}
			if [ "${a}" = "${b}" ]; then
				eval a=\$QUALITY_${i}
				eval b=\$QUALITY_${k}
				local u=${k}
				# We need to split this into two tests, otherwise bash errors
				[ -n "${a}" -a -n "${b}" ] && [ "${a}" -lt "${b}" ] && u=${i}
				unset MAC_${u} SSID_${u} MODE_${u} CHAN_${u} QUALITY_${u} ENC_${u}
			fi
			: $(( k += 1 ))
		done
		: $(( i += 1 ))
	done

	local i=0 e= m= s=

	while [ ${i} -le ${APS} ]; do
		eval x=\$MAC_${i}
		if [ -z "${x}" ]; then
		    : $(( i += 1 ))
		    continue
		fi

		eval m=\$MODE_${i}
		eval s=\$SSID_${i}
		eval q=\$QUALITY_${i}
		eval e=\$ENC_${i}
		if [ -n "${e}" -a "${e}" != "off" ]; then
		    e=", encrypted"
		else
		    e=""
		fi
		if [ -z "${s}" ]; then
			einfo "Found ${x}, ${m}${e}"
		else
			einfo "Found \"${s}\" at ${x}, ${m}${e}"
		fi

		x="$(echo "${x}" | sed -e 's/://g')"
		eval x=\$mac_ssid_${x}
		if [ -n "${x}" ]; then
			eval SSID_${i}=\$x
			s=${x}
			eindent
			einfo "mapping to \"${x}\""
			eoutdent
		fi

		eval set -- $(_flatten_array "blacklist_aps_${IFVAR}")
		[ $# = 0 ] && eval set -- $(_flatten_array "blacklist_aps")
		for x; do
			if [ "${x}" = "${s}" ]; then
				ewarn "${s} has been blacklisted - not connecting"
				unset SSID_${i} MAC_${i} ${MODE}_${i} CHAN_${i} QUALITY_${i} ENC_${i}
			fi
		done
		: $(( i += 1 ))
	done
	eoutdent
}

iw_force_preferred()
{
	eval set -- $(_flatten_array "preferred_aps_${IFVAR}")
	[ $# = 0 ] && eval set -- $(_flatten_array "preferred_aps")
	[ $# = 0 ] && return 1

	ewarn "Trying to force preferred in case they are hidden"
	for ssid; do
		local found_AP=false i=0 e=
		while [ ${i} -le ${APS} ]; do
			eval e=\$SSID_${i}
			if [ "${e}" = "${ssid}" ]; then
				found_AP=true
				break
			fi
			: $(( i += 1 ))
		done
		if ! ${found_AP}; then
			SSID=${ssid}
			iw_associate && return 0
		fi
	done

	ewarn "Failed to associate with any preferred access points on ${IFACE}"
	return 1
}

iw_connect_preferred()
{
	local ssid= i= mode= mac= enc= freq= chan=
	eval set -- $(_flatten_array "preferred_aps_${IFVAR}")
	[ $# = 0 ] && eval set -- $(_flatten_array "preferred_aps")

	for ssid; do
		unset IFS
		i=0
		while [ ${i} -le ${APS} ]; do
			eval e=\$SSID_${i}
			if [ "${e}" = "${ssid}" ]; then
				SSID=${e}
				eval mode=\$MODE_${i}
				eval mac=\$MAC_${i}
				eval enc=\$ENC_${i}
				eval freq=\$FREQ_${i}
				eval chan=\$CHAN_${i}
				iw_associate "${mode}" "${mac}" "${enc}" "${freq}" \
					"${chan}" && return 0
			fi
			: $(( i += 1 ))
		done
	done

	return 1
}

iw_connect_not_preferred()
{
	local ssid= i=0 mode= mac= enc= freq= chan= pref=false

	while [ ${i} -le ${APS} ]; do
		eval e=\$SSID_${i}
		if [ -n "${e}" ]; then
			eval set -- $(_flatten_array "preferred_aps_${IFVAR}")
			[ $# = 0 ] && eval set -- $(_flatten_array "preferred_aps")
			for ssid; do
				if [ "${e}" = "${ssid}" ]; then
					pref=true
					break
				fi
			done

			if ! ${pref}; then
				SSID=${e}
				eval mode=\$MODE_${i}
				eval mac=\$MAC_${i}
				eval enc=\$ENC_${i}
				eval freq=\$FREQ_${i}
				eval chan=\$CHAN_${i}
				iw_associate "${mode}" "${mac}" "${enc}" "${freq}" \
					"${chan}" && return 0
			fi
		fi
		: $(( i += 1 ))
	done

	return 1
}

iw_defaults()
{
	# Turn on the radio
	iw dev "${IFACE}" set txpower auto 2>/dev/null

	iw dev "${IFACE}" disconnect 2>/dev/null
	iw dev "${IFACE}" ibss leave 2>/dev/null
}

iw_configure()
{
	local x= APS=-1
	eval SSID=\$ssid_${IFVAR}

	# Support old variable
	[ -z "${SSID}" ] && eval SSID=\$essid_${IFVAR}

	# Setup ad-hoc mode?
	eval _mode=\$mode_${IFVAR}
	_mode=${_mode:-managed}

	case "${_mode}" in
		master)
			eerror "Please use hostapd to make this interface an access point"
			return 1
			;;
		ad-hoc|adhoc)
			iw_setup_adhoc
			return $?
			;;
		managed)
			# Fall through
			;;
		mesh)
			iw_setup_mesh
			return $?
			;;
		*)
			eerror "Only managed and ad-hoc are supported"
			return 1
			;;
	esac

	# Has an SSID been forced?
	if [ -n "${SSID}" ]; then
		iw_set_mode "${_mode}"
		iw_associate && return 0
		[ "${SSID}" = "any" ] && iw_force_preferred && return 0

		eval SSID=\$adhoc_ssid_${IFVAR}
		if [ -n "${SSID}" ]; then
			iw_setup_adhoc
			return $?
		fi
		return 1
	fi

	_up

	eval x=\$preferred_aps_${IFVAR}
	[ -n "${x}" ] && preferred_aps=${x}

	eval x=\$blacklist_aps_${IFVAR}
	[ -n "${x}" ] && blacklist_aps=${x}

	eval x=\$associate_order_${IFVAR}
	[ -n "${x}" ] && associate_order=${x}
	associate_order=${associate_order:-any}

	if [ "${associate_order}" = "forcepreferredonly" ]; then
		iw_force_preferred && return 0
	else
		iw_scan || return 1
		iw_connect_preferred && return 0
		[ "${associate_order}" = "forcepreferred" ] || \
		[ "${associate_order}" = "forceany" ] && \
		iw_force_preferred && return 0
		[ "${associate_order}" = "any" ] || \
		[ "${associate_order}" = "forceany" ] && \
		iw_connect_not_preferred && return 0
	fi

	e="associate with"
	[ -z "${MAC_0}" ] && e="find"
	[ "${preferred_aps}" = "force" ] || \
	[ "${preferred_aps}" = "forceonly" ] && \
	e="force"
	e="Couldn't ${e} any access points on ${IFACE}"

	eval SSID=\$adhoc_ssid_${IFVAR}
	if [ -n "${SSID}" ]; then
		ewarn "${e}"
		iw_setup_adhoc
		return $?
	fi

	eerror "${e}"
	return 1
}

iw_pre_start()
{
	# We don't configure wireless if we're being called from
	# the background
	yesno ${IN_BACKGROUND} && return 0

	service_set_value "SSID" ""
	_exists || return 0

	if ! _is_wireless; then
		veinfo "${IFACE} does not appear to be a wireless interface"
		return 0
	fi

	# Store the fact that tx-power was off so we default to a longer
	# wait if our scan returns nothing
	LC_ALL=C iw dev "${IFACE}" info | sed -e '1d' | grep -Fq "txpower 0.00"
	local txpowerwasoff=$?

	iw_defaults
	iw_user_config

	# Set the base metric to be 2000
	metric=2000

	# Check for rf_kill - only ipw supports this at present, but other
	# cards may in the future.
	if [ -e /sys/class/net/"${IFACE}"/device/rf_kill ]; then
		if [ $(cat /sys/class/net/"${IFACE}"/device/rf_kill) != "0" ]; then
			eerror "Wireless radio has been killed for interface ${IFACE}"
			return 1
		fi
	fi

	einfo "Configuring wireless network for ${IFACE}"

	# Are we a proper IEEE device?
	# Most devices reutrn IEEE 802.11b/g - but intel cards return IEEE
	# in lower case and RA cards return RAPCI or similar
	# which really sucks :(
	# For the time being, we will test prism54 not loading firmware
	# which reports NOT READY!
	x="$(iw_get_type)"
	if [ "${x}" = "NOT READY!" ]; then
		eerror "Looks like there was a problem loading the firmware for ${IFACE}"
		return 1
	fi

	if iw_configure; then
		service_set_value "SSID" "${SSID}"
		return 0
	fi

	eerror "Failed to configure wireless for ${IFACE}"
	iw_defaults
	iw dev "${IFACE}" set txpower fixed 0 2>/dev/null
	unset SSID SSIDVAR
	_down
	return 1
}

iw_post_stop()
{
	yesno ${IN_BACKGROUND} && return 0
	_exists || return 0
	iw_defaults
	iw dev "${IFACE}" set txpower fixed 0 2>/dev/null
}
