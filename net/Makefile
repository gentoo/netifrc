DIR=	${LIBEXECDIR}/net
SRCS=	ifconfig.sh.in ${SRCS-${OS}}
INC=	dhclient.sh dhcpcd.sh ifconfig.sh macchanger.sh macnet.sh \
	ssidnet.sh system.sh wpa_supplicant.sh ${INC-${OS}}

MK=	../mk
include ${MK}/os.mk

SRCS-FreeBSD=	iwconfig.sh.in
INC-FreeBSD=	iwconfig.sh

SRCS-Linux=	iwconfig.sh.in udhcpc.sh.in
INC-Linux=	adsl.sh apipa.sh arping.sh bonding.sh br2684ctl.sh bridge.sh \
		ccwgroup.sh clip.sh ethtool.sh iproute2.sh iptoken.sh ifplugd.sh ip6to4.sh \
		ipppd.sh iwconfig.sh netplugd.sh pppd.sh tuntap.sh udhcpc.sh \
		vlan.sh macvlan.sh ip6rd.sh firewalld.sh dummy.sh hsr.sh l2tp.sh \
		iw.sh iwd.sh wireguard.sh veth.sh dhclientv6.sh qmi.sh

SRCS-NetBSD= ifwatchd.sh.in
INC-NetBSD=	ifwatchd.sh

%.sh.in: %.sh${SFX}
	${CP} $< $@

include ${MK}/scripts.mk
