# rules to make a distribution tarball from a git repo
# Copyright (c) 2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.

GITREF?=	HEAD
DISTPREFIX?=	${NAME}-${VERSION}
DISTFILE?=	${DISTPREFIX}.tar.xz

CLEANFILES+=	${NAME}-*.tar.xz

_SNAP_SH=	date -u +%Y%m%d%H%M
_SNAP:=		$(shell ${_SNAP_SH})
SNAP=		${_SNAP}
SNAPDIR=	${DISTPREFIX}-${SNAP}
SNAPFILE=	${SNAPDIR}.tar.xz

gitdist:
	git archive --prefix=${DISTPREFIX}/ ${GITREF} | xz > ${DISTFILE}

dist:
	sh -c ' \
	D=$$(mktemp -d) && \
	mkdir $${D}/${DISTPREFIX} && \
	git checkout-index -f -a --prefix=$${D}/${DISTPREFIX}/ && \
	git log >$${D}/${DISTPREFIX}/ChangeLog && \
	gtar cjf ${DISTFILE} --owner=0 --group=0 --format=posix --mode=a+rX -C $$D ${DISTPREFIX} && \
	rm -rf $$D '

distcheck: dist
	rm -rf ${DISTPREFIX}
	gtar xf ${DISTFILE}
	MAKEFLAGS= $(MAKE) -C ${DISTPREFIX}
	MAKEFLAGS= $(MAKE) -C ${DISTPREFIX} check
	rm -rf ${DISTPREFIX}

snapshot:
	rm -rf /tmp/${SNAPDIR}
	mkdir /tmp/${SNAPDIR}
	cp -RPp * /tmp/${SNAPDIR}
	(cd /tmp/${SNAPDIR}; make clean)
	find /tmp/${SNAPDIR} -name .svn -exec rm -rf -- {} \; 2>/dev/null || true
	gtar -cvjpf ${SNAPFILE} -C /tmp ${SNAPDIR}
	rm -rf /tmp/${SNAPDIR}
	ls -l ${SNAPFILE}

snap: snapshot

