#!/bin/bash

available_ramsize() { LANG=C free -g | awk '/^Mem:/{print $NF}'; }

vmmax=$1
if [[ "$vmmax" =~ ^vmmax=[0-9]+$ ]]; then
	vmmax=${vmmax#vmmax=}; shift
else
	availableMemSize=$(available_ramsize)
	vmmax=$((availableMemSize/4))
fi

[[ $# -eq 0 ]] && { echo "Usage: <$0> [vmmax=N] <distro> [vm-create-options]"; exit 1; }
TS=$(tmux ls | awk -F: '/fsparallel-test-/ {print $1}')
for ts in ${TS}; do tmux kill-session -t ${ts}; done

testarr=($(find . -name main*.sh|grep -v ontap))
while :; do
	vmn=$(LANG=C vm ls|grep running|wc -l)
	[[ "${#testarr[@]}" = 0 ]] && { echo "[INFO] all tests submmitted."; break; }
	echo "{INFO} $vmn/$vmmax VM is running"
	if [[ $vmmax -gt $vmn ]]; then
		testn=$(((vmmax-vmn)/3))
		[[ "$testn" -gt ${#testarr[@]} ]] && testn=${#testarr[@]}
		totest=("${testarr[@]::${testn}}")
		testarr=("${testarr[@]:${testn}}")
		for f in "${totest[@]}"; do
			#$f "$@";   #$distro $vm-create-options
			echo [run] tmux new -d \"$f $*\"
			tmux new -s "fsparallel-test-${f#./}" -d "$f $*"
		done
		sleep 10m
	else
		sleep 10m
	fi
done

ontaptestarr=($(find . -name main*ontap*.sh))
for f in "${ontaptestarr[@]}"; do
	$f "$@"
done
