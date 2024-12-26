#!/bin/bash

available_ramsize() { LANG=C free -g | awk '/^Mem:/{print $NF}'; }
get_vmmax() {
	local mempervm=${1:-4}
	local availablemem=$(available_ramsize)
	echo $((availablemem/mempervm))
}

avg_msize=4  #per VM
avg_vmcnt=3  #per test
vmmax=$1
if [[ "$vmmax" =~ ^vmmax=[0-9]+$ ]]; then
	vmmax=${vmmax#vmmax=}; shift
else
	vmmax=$(get_vmmax $avg_msize)
fi

[[ $# -eq 0 ]] && { echo "Usage: <$0> [vmmax=N] <distro> [vm-create-options]"; exit 1; }
for ts in $(tmux ls 2>/dev/null | awk -F: '/fsparallel-test/ {print $1}'); do tmux kill-session -t ${ts}; done
for ts in $(tmux ls 2>/dev/null | awk -F: '/kissrun-/ {print $1}'); do tmux kill-session -t ${ts}; done

ontap_vmmax=6
if [[ $vmmax -ge $ontap_vmmax ]]; then
	echo -e "{INFO $(date +%F_%T)} submit ontap-simulator related test cases in background ..."
	tmux new -s fsparallel-test-ontap/ -d bash -c '
		ontaptestarr=($(find . -name main*ontap*.sh))
		for f in "${ontaptestarr[@]}"; do
			$f "$@"
		done'
	sleep 5
	tmux ls
	let vmmax-=$ontap_vmmax
fi

testarr=($(find . -name main*.sh|grep -v ontap))
while :; do
	[[ "${#testarr[@]}" = 0 ]] && { echo "{INFO $(date +%F_%T)} all tests submmitted."; break; }
	if [[ $vmmax -ge $((2*avg_vmcnt)) ]]; then
		echo -e "\n{INFO $(date +%F_%T)} vmmax=$vmmax(>=2*avg_vmcnt($avg_vmcnt)), submit more tests ..."
		testn=$((vmmax/avg_vmcnt))
		[[ "$testn" -gt ${#testarr[@]} ]] && testn=${#testarr[@]}
		totest=("${testarr[@]::${testn}}")
		testarr=("${testarr[@]:${testn}}")
		for f in "${totest[@]}"; do
			sessionName="fsparallel-test-${f#./}"
			echo [run] tmux new -s $sessionName -d \"$f $*\"
			tmux new -s "$sessionName" -d "$f $*"
		done
		sleep 8m
	else
		echo -e "\n{INFO $(date +%F_%T)} vmmax=$vmmax(<2*avg_vmcnt($avg_vmcnt)), waiting some tests finish ..."
		sleep 8m
	fi
	vmmax=$(get_vmmax $avg_msize)
done

while :; do
	echo -e "\n{INFO $(date +%F_%T)} waiting all tests done ..."
	if tmux ls 2>/dev/null | grep fsparallel-test; then
		sleep 5m;
	else
		echo -e "\n{INFO $(date +%F_%T)} all tests have done, please check the results:"
		ls -l $(ls ~/testres/* -1td|head -1)
		break
	fi
done
