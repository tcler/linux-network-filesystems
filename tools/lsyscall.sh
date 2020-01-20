#!/bin/bash

tableurl=https://raw.githubusercontent.com/hrw/syscalls-table/master/tables
arch=$(arch)
  is_available_url() { curl --connect-timeout 8 -m 16 --output /dev/null --silent --head --fail $1 &>/dev/null; }
  is_intranet() { is_available_url http://download.devel.redhat.com; }
  is_intranet && tableurl=http://download.devel.redhat.com/qa/rhts/lookaside/syscalls-table/tables

case $1 in
alpha|arc|arm|arm64|armoabi|avr32|blackfin|c6x|cris|csky|frv|h8300|hexagon|i386|ia64|m32r|m68k|metag|microblaze|mips64|mips64n32|mipso32|mn10300|nds32|nios2|openrisc|parisc|powerpc|powerpc64|riscv32|riscv64|s390|s390x|score|sh|sh64|sparc|sparc64|tile|tile64|unicore32|x32|x86_64|xtensa)
	arch=$1; shift;;
esac

tablefurl=$tableurl/syscalls-${arch}
tables=$(curl -s -L $tablefurl)

if [[ $# = 0 ]]; then
	echo "$tables"
else
	for syscall; do
		awk -v call=$syscall '$1 == call || $2 == call' <<<"$tables"
	done
fi
