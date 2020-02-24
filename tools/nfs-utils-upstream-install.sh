#!/bin/bash

gitUrl=git://git.linux-nfs.org/projects/steved/nfs-utils.git

yum install -y /usr/bin/aclocal /usr/bin/libtoolize rpcgen libtirpc-devel \
    libevent-devel sqlite-devel device-mapper-devel libblkid-devel krb5-devel git

git clone $gitUrl
pushd nfs-utils
	./autogen.sh
	./configure
	make && make install
popd

mount.nfs -V
