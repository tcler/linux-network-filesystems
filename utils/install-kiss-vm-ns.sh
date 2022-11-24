#!/bin/bash

switchroot() {
        local P=$0 SH=; [[ $0 = /* ]] && P=${0##*/}; [[ -e $P && ! -x $P ]] && SH=$SHELL
        [[ $(id -u) != 0 ]] && {
                echo -e "\E[1;30m{WARN} $P need root permission, switch to:\n  sudo $SH $P $@\E[0m"
                exec sudo $SH $P "$@"
        }
}
switchroot "$@"

gitrepo=https://github.com/tcler/kiss-vm-ns
rpm -q git make &>/dev/null || yum install -y git make
while true; do
	git clone $gitrepo && make -C kiss-vm-ns
	which vm && break
	echo -e "{warn} installing kiss-vm-ns fail, try again ..."
done
rm -rf kiss-vm-ns

vm prepare
