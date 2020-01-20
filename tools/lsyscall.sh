#!/bin/bash

Arch=$(arch)
case $1 in
alpha|arc|arm|arm64|armoabi|avr32|blackfin|c6x|cris|csky|frv|h8300|hexagon|i386|ia64|m32r|m68k|metag|microblaze|mips64|mips64n32|mipso32|mn10300|nds32|nios2|openrisc|parisc|powerpc|powerpc64|riscv32|riscv64|s390|s390x|score|sh|sh64|sparc|sparc64|tile|tile64|unicore32|x32|x86_64|xtensa)
	Arch=$1; shift;;
esac

ausyscall() {
	if [[ $# = 0 ]]; then
		command ausyscall --dump | awk '{print $2, $1}'
	else
		local call=$1
		local num=$call
		local name=
		read name num < <(command ausyscall $Arch $call 2>/dev/null)
		if [[ -n "$name" ]]; then
			echo $name $num
		else
			return 1
		fi
	fi
}

lsyscall() {
	local tableurl=https://raw.githubusercontent.com/hrw/syscalls-table/master/tables
	is_available_url() { curl --connect-timeout 8 -m 16 --output /dev/null --silent --head --fail $1 &>/dev/null; }
	is_intranet() { is_available_url http://download.devel.redhat.com; }
	is_intranet && tableurl=http://download.devel.redhat.com/qa/rhts/lookaside/syscalls-table/tables

	local tablefurl=$tableurl/syscalls-${Arch}
	local tables=$(curl -s -L $tablefurl)

	if [[ $# = 0 ]]; then
		echo "$tables"
	else
		local call=$1
		awk -v call=$call '$1 == call || $2 == call' <<<"$tables"
	fi
}

ausyscall "$@" || lsyscall "$@"