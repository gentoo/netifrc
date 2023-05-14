# Copyright (c) 2011 by Gentoo Foundation
# Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008

_is_qmi() {
	[ -d "/sys/class/net/${IFACE}/qmi" ]
}

_get_state() {
	echo "/run/net.${IFACE}.qmi.state"
}

_get_device() {
	echo "/dev/cdc-$(echo "${IFACE}" | sed 's/wwan/wdm/')"
}

qmi_depend()
{
	program qmicli
	program ip
	before interface
}

qmi_pre_start() {

	_is_qmi || return 0

	local device
	local apn
	local auth
	local username
	local password
	local out
	local rc

	eval device=\$qmi_cdc_${IFVAR}
	eval apn=\$qmi_apn_${IFVAR}
	eval auth=\$qmi_auth_${IFVAR}
	eval username=\$qmi_username_${IFVAR}
	eval password=\$qmi_password_${IFVAR}

	[ -n "${apn}" ] || return 0

	[ -n "${device}" ] || device="$(_get_device)"
	[ -n "${auth}" ] || auth="none"
	[ -n "${username}" ] || username="dummy"
	[ -n "${password}" ] || password="dummy"

	if ! [ -c "${device}" ]; then
		ewarn "Cannot open device ${device} for ${IFACE}, aborting configuration"
		return 1
	fi

	if ! cat "/sys/class/net/${IFACE}/qmi/raw_ip" | grep -q Y; then
		ebegin "Configuring QMI raw IP"

		ip link set "${IFACE}" down
		if ! echo Y > "/sys/class/net/${IFACE}/qmi/raw_ip"; then
			eend 1 "Cannot set raw IP mode for ${IFACE}, aborting configuration"
			return 1
		else
			eend 0
		fi
	fi

	local wwan_connection="apn='${apn}',auth='${auth}',username='${username}',password='${password}',autoconnect=yes,ip-type=4"
	local n
	for n in 1 2 3; do
		ebegin "Connecting QMI APN '${apn}' using '${username}'"

		if out="$( \
			qmicli \
				--device="${device}" \
				--wds-start-network="${wwan_connection}" \
				--device-open-proxy \
				--client-no-release-cid \
		)"; then
			eend 0
			break
		elif echo "${out}" | grep -qi "timed out"; then
			eend 1 "QMI start network timeout"
		else
			eend 1 "QMI start network failed for ${IFACE}, aborting"
			return 1
		fi
	done

	local handle="$(echo "${out}" | grep "Packet data handle:" | sed "s/.*'\(.*\)'.*/\1/")"
	local cid="$(echo "${out}" | grep "CID:" | sed "s/.*'\(.*\)'.*/\1/")"

	if [ -z "${handle}" ]; then
		ewarn 1 "No QMI connection handle ${IFACE}, aborting configuration"
		return 1
	fi

	if [ -z "${cid}" ]; then
		ewarn "No QMI connection id ${IFACE}, aborting configuration"
		return 1
	fi

	cat > "$(_get_state)" << __EOF__
device="${device}"
handle="${handle}"
cid="${cid}"
__EOF__
}

qmi_post_stop() {

	_is_qmi || return 0

	local state="$(_get_state)"

	[ -f "${state}" ] || return 0

	ebegin "Disconnecting QMI ${IFACE}"

	local device
	local handle
	local cid

	. "${state}"

	qmicli \
		--device="${device}" \
		--client-cid="${cid}" \
		--wds-stop-network="${handle}"
	rc="$?"

	rm -f "${state}"

	eend "${rc}"
}
