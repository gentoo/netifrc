#!/bin/sh
# Copyright (C) 2026 Gentoo Foundation
# All rights reserved. Released under the 2-clause BSD license.
# shellcheck shell=sh disable=SC1008
#
# This file gets called by ifplugd when it wants to bring an
# interface up or down.

if grep -q initng /proc/1/cmdline
then
    EXEC="/sbin/ngc"
    INITNG="yes"
else
    EXEC="/etc/init.d/net.$1"
    INITNG="no"
fi

case "$2" in
    up)
	if [ "${INITNG}" = "yes" ]
	then
	    ARGS="-u net/$1"
	else
	    ARGS="--quiet start"
	fi
	;;
    down)
	if [ "${INITNG}" = "yes" ]
	then
	    ARGS="-d net/$1"
	else
	    ARGS="--quiet stop"
	fi
	;;
    *)
	echo "$0: wrong arguments" >&2
	echo "Call with <interface> <up|down>" >&2
	exit 1
	;;
esac

export IN_BACKGROUND=true

if [ -x "${EXEC}" ]
then
    ${EXEC} ${ARGS}
    exit 0
else
    logger -t ifplugged.sh "Error: Couldn't configure $1, no ${EXEC} !"
    exit 1
fi

# vim: set ts=4
