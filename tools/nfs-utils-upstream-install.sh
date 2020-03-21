#!/bin/bash

RC=1
gitUrl=git://git.linux-nfs.org/projects/steved/nfs-utils.git

yum install -y /usr/bin/aclocal /usr/bin/libtoolize rpcgen libtirpc-devel \
    libevent-devel sqlite-devel device-mapper-devel libblkid-devel krb5-devel git

if git clone $gitUrl; then
	pushd nfs-utils
		if ./autogen.sh && ./configure && make && make install; then
			mount.nfs -V
			RC=0
		fi
	popd
fi

exit $RC
