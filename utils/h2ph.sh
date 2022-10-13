#!/bin/bash

LANG=C
P=$0
[[ $0 = /* ]] && P=${0##*/}
AT=("$@")

switchroot() {
	[[ $(id -u) != 0 ]] && {
		echo -e "{NETNS:WARN} $P need root permission, switch to:\n  sudo $P ${AT[@]}" | GREP_COLORS='ms=1;30' grep --color=always . >&2
		exec sudo $P "${AT[@]}"
	}
}
switchroot

which h2ph 2>/dev/null ||
	yum install -y /usr/bin/h2ph
mkdir -p /usr/local/lib64/perl5
IDIR=/usr/include
CMD="h2ph -Q -r -l ."

cd $IDIR
echo "{root@local $IDIR}> $CMD"
$CMD
