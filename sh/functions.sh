# Compatibility layer for netifrc to work with multiple init
# systems.

# First check whether e* commands are present in the environment
if [ x$RC_GOT_FUNCTIONS = xyes -o -n "$(command -v ebegin 2>/dev/null)" ]; then
	:

# Then check for the presence of functions.sh
elif [ -f /lib/gentoo/functions.sh ]; then
	. /lib/gentoo/functions.sh

else
	echo "/lib/gentoo/functions.sh not found. Exiting"
	exit 1
fi

# runscript functions
# TODO: if another non-openrc system provides these in future, we have to
# change this structure.
if [ "$INIT" != "openrc" ]; then

	# OpenRC functions used in depend
	after() {
		:
	}
	before() {
		:
	}
	program() {
		:
	}
	need() {
		:
	}

	shell_var() {
		local output= sanitized_arg=
		for arg; do
			sanitized_arg=$arg
			while :; do
				case $sanitized_arg in
				*[!a-zA-Z0-9_]*)
					sanitized_arg=${sanitized_arg%%[!a-zA-Z0-9_]*}_${sanitized_arg#*[!a-zA-Z0-9_]}
					continue;;
				esac
				break
			done
			if [ x"$output" = x"" ] ; then
				output=$sanitized_arg
			else
				output="$output $sanitized_arg"
			fi
		done
		echo "$output"
	}

	net_fs_list="afs ceph cifs coda davfs fuse fuse.sshfs gfs glusterfs lustre ncpfs nfs nfs4 ocfs2 shfs smbfs"
	is_net_fs()
	{
		[ -z "$1" ] && return 1

		local fs=$(mount | grep " on $1 " | cut -f 5 -d ' ')
		for x in $fs; do
			for y in $net_fs_list; do
				[ "$x" = "$y" ] && return 0
			done
		done
		return 1
	}

	service_set_value() {
		local OPTION="$1" VALUE="$2"
		if [ -z "$OPTION" ]; then
			eerror "service_set_value requires parameter KEY"
			return
		fi
		local file="$OPTIONSDIR/${OPTION}"
		echo "$VALUE" > $file
	}
	service_get_value() {
		local OPTION="$1"
		if [ -z "$OPTION" ]; then
			eerror "service_get_value requires parameter KEY"
			return
		fi
		local file="$OPTIONSDIR/${OPTION}"
		cat $file 2>/dev/null
	}
	STATEFILE="${STATEDIR}/state"
	# Internal Function
	# Stores the state of netifrc in ${SVCDIR}/${SVCNAME}/state file
	_mark_service() {
		local state=$1
		echo $state > $STATEFILE
	}
	#Internal Function
	# Checks whether the state of netifrc is same as $1
	_service_state() {
		state=$(cat $STATEFILE 2>/dev/null)
		if [ state = $1 ]; then
			return 1
		fi
		return 0
	}

	mark_service_started() {
		_mark_service started
	}
	mark_service_inactive() {
		_mark_service inactive
	}
	mark_service_stopped() {
		_mark_service stopped
	}
	service_started() {
		_service_state started
		return $?
	}
	service_inactive() {
		_service_state inactive
		return $?
	}
fi

# Extracts the interface for the current invocation
get_interface() {
	case $INIT in
		openrc)
			printf ${RC_SVCNAME#*.};;
		systemd)
			printf ${RC_IFACE};;
		*)
			eerror "Init system not supported. Aborting"
			exit 1;;
	esac
}

# vim: ts=4 sw=4 noexpandtab
