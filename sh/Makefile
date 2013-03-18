DIR=	${LIBEXECDIR}/sh
SRCS= ${SRCS-${OS}}
INC=
BIN=	${BIN-${OS}}

MK=	../mk
include ${MK}/os.mk

SRCS-FreeBSD=
BIN-FreeBSD=

SRCS-Linux=	udhcpc-hook.sh.in
BIN-Linux=	udhcpc-hook.sh

SRCS-NetBSD=	ifwatchd-carrier.sh.in ifwatchd-nocarrier.sh.in
BIN-NetBSD=	ifwatchd-carrier.sh ifwatchd-nocarrier.sh

include ${MK}/scripts.mk

%.sh: %.sh${SFX}
	${SED} ${SED_REPLACE} ${SED_EXTRA} $< > $@
