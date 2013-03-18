DIR=	${INITDIR}
INSTALLAFTER=	_installafter_net.lo
SRCS= net.lo.in
BIN=	${OBJS}

# Build our old net foo or not

MK=	../mk
include ${MK}/os.mk

NET_LO-FreeBSD=	net.lo0
NET_LO-Linux=	net.lo
NET_LO-NetBSD=	net.lo0

%.in: %${SFX}
	sed ${SED_REPLACE} ${SED_EXTRA} $< > $@

include ${MK}/scripts.mk

_installafter_: realinstall

_installafter_net.lo: realinstall
	${INSTALL} -m ${BINMODE} net.lo ${DESTDIR}/${INITDIR}/${NET_LO-${OS}}
