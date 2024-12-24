#!/bin/bash

available_ramsize() { LANG=C free -g | awk '/^Mem:/{print $NF}'; }
get_vmmax() {
	local mempervm=${1:-4}
	local availablemem=$(available_ramsize)
	echo $((availablemem/mempervm))
}

vmmax=$1
if [[ "$vmmax" =~ ^vmmax=[0-9]+$ ]]; then
	vmmax=${vmmax#vmmax=}; shift
else
	vmmax=$(get_vmmax 4)
fi

[[ $# -eq 0 ]] && { echo "Usage: <$0> [vmmax=N] <distro> [vm-create-options]"; exit 1; }
for ts in $(tmux ls | awk -F: '/fsparallel-test/ {print $1}'); do tmux kill-session -t ${ts}; done
for ts in $(tmux ls | awk -F: '/kissrun-/ {print $1}'); do tmux kill-session -t ${ts}; done

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
			sessionName="fsparallel-test-${f#./}"
			echo [run] tmux new -s $sessionName -d \"$f $*\"
			tmux new -s "$sessionName" -d "$f $*"
		done
		sleep 10m
	else
		sleep 10m
	fi
	vmmax=$(get_vmmax 4)
done

tmux new -s fsparallel-test-ontap/ bash -c '
	ontaptestarr=($(find . -name main*ontap*.sh))
	for f in "${ontaptestarr[@]}"; do
		$f "$@"
	done'
