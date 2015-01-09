DIR=	${LIBEXECDIR}/sh
SRCS= ${SRCS-${OS}}
INC=
BIN=	${BIN-${OS}}

MK=	../mk
include ${MK}/os.mk

SRCS-FreeBSD=
BIN-FreeBSD= functions.sh

SRCS-Linux=	udhcpc-hook.sh.in systemd-wrapper.sh.in
BIN-Linux=	udhcpc-hook.sh functions.sh systemd-wrapper.sh

SRCS-NetBSD=	ifwatchd-carrier.sh.in ifwatchd-nocarrier.sh.in
BIN-NetBSD=	ifwatchd-carrier.sh ifwatchd-nocarrier.sh functions.sh

include ${MK}/scripts.mk

%.sh: %.sh${SFX}
	${SED} ${SED_REPLACE} ${SED_EXTRA} $< > $@
