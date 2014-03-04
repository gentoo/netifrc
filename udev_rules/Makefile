DIR=		${UDEVDIR}/rules.d
SRCS=		${SRCS-${OS}}
INC=		${INC-${OS}}

MK=	../mk
include ${MK}/os.mk

SRCS-Linux=	90-network.rules
INC-Linux=	90-network.rules

include ${MK}/scripts.mk
