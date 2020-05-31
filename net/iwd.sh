# Original copyright (c) 2007-2009 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.

iwd_depend()
{
	need dbus
	after macnet plug
	before interface
	provide wireless
	after iwconfig
	program iwd
}

_config_vars="$_config_vars iwd"

iwd_pre_start()
{
	local iwds=/usr/libexec/iwd
	local args= opt= opts=
	eval opts=\$iwd_${IFVAR}

	#set a "safe" default in case phy was not defined
	PHY="phy0"

	for opt in ${opts}; do
		case "${opt}" in
			phy* )	PHY="${opt}"
				einfo "Assigned PHY to be ${PHY}"
				;;
			*    )	;;
		esac
	done
	ebegin "Starting iwd on ${PHY} and ${IFVAR}"
	pidfile="/run/iwd-${IFVAR}.pid"
	start-stop-daemon --start --exec "${iwds}" --pidfile "${pidfile}" --background --verbose --make-pidfile -- -p ${PHY} -i "${IFVAR}"
	return $?
}


iwd_post_stop()
{
	local iwds=/usr/libexec/iwd
	pidfile="/run/iwd-${IFVAR}.pid"
	if [ -f ${pidfile} ]; then
		ebegin "Stopping iwd on ${IFACE}"
		start-stop-daemon --stop --exec "${iwds}" --pidfile "${pidfile}"
		eend $?
	fi

	# If iwd exits uncleanly, we need to remove the stale dir
	[ -S "/run/iwd/${IFACE}" ] \
		&& rm -f "/run/iwd/${IFACE}"
}

