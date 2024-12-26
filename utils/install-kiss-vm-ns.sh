#!/bin/bash

switchroot() {
        local P=$0 SH=; [[ $0 = /* ]] && P=${0##*/}; [[ -e $P && ! -x $P ]] && SH=$SHELL
        [[ $(id -u) != 0 ]] && {
                echo -e "\E[1;4m{WARN} $P need root permission, switch to:\n  sudo $SH $P $@\E[0m"
                exec sudo $SH $P "$@"
        }
}
switchroot "$@"

install_kiss_tools() {
	local _repon=kiss-vm-ns
	local url=https://github.com/tcler/${_repon}/archive/refs/heads/master.tar.gz
	local tmpdir=$(mktemp -d)
	while ! command -v vm; do
		rm -rf $tmpdir/${_repon}-master
		curl -k -Ls $url | tar zxf - -C $tmpdir &&
			gmake -C $tmpdir/${_repon}-master &&
			break
	done
	rm -rf $tmpdir
}

install_kiss_tools
vm prepare
