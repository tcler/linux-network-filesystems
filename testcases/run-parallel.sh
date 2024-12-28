#!/bin/bash

export LANG=C
P=${0##*/}

avg_msize=4  #per VM
avg_vmcnt=3  #per test
available_ramsize() { LANG=C free -g | awk '/^Mem:/{print $NF}'; }
get_vmmax() {
	local mempervm=${1:-4}
	local availablemem=$(available_ramsize)
	echo $((availablemem/mempervm))
}

Usage() {
	echo "Usage: $P [-h] [--no|--no-ontap] [-f <path-pattern>] <distro> [vm-create-options]";
	echo "  e.g: $P --no-ontap RHEL-8.10.0"
	echo "  e.g: $P -f ontap RHEL-9.5.0"
	echo "  e.g: $P -f nfstest.cache RHEL-10.0"
}
while true; do
	case "$1" in
	-h|--help)	Usage; shift 1; exit 0;;
	-f|--filter)	pathPattern=$2; shift 2;;
	--no|--noontap)	noOntap=yes; shift 1; exit 0;;
	*)		break;;
	esac
done

[[ $# -eq 0 ]] && { Usage; exit 1; }
for ts in $(tmux ls 2>/dev/null | awk -F: '/fsparallel-test/ {print $1}'); do tmux kill-session -t ${ts}; done
for ts in $(tmux ls 2>/dev/null | awk -F: '/kissrun-/ {print $1}'); do tmux kill-session -t ${ts}; done

[[ "$noOntap" = yes ]] && grepOpt='-v ontap.*.sh'
pattern=${pathPattern:-.}
tests=$(find . -name main*.sh | grep -E $pattern $grepOpt)
ontapTests=$(grep -E  ontap <<<"$tests")
otherTests=$(grep -Ev ontap <<<"$tests")

if [[ -z "${otherTests}" && -z "${ontapTests}" ]]; then
	echo "{WARN} no tests match pattern. do nothing" >&2
	exit
fi

[[ -n "${ontapTests}" ]] && echo -e "Ontap related tests:\n ${ontapTests//$'\n'/$'\n' }"
[[ -n "${otherTests}" ]] && echo -e "Other tests:\n ${otherTests//$'\n'/$'\n' }"

vmmax=$(get_vmmax $avg_msize)
ontap_vmmax=6
if [[ -n "${ontapTests}" && $vmmax -ge $ontap_vmmax ]]; then
	echo -e "{INFO $(date +%F_%T)} submit ontap-simulator related test cases in background ..."
	tmux new -s fsparallel-test-ontap/ -d bash -c "for f in ${ontapTests//$'\n'/ }; do \$f $*; done"
	sleep 5
	tmux ls
	let vmmax-=$ontap_vmmax
fi

if [[ -n "${otherTests}" ]]; then
	otArray=(${otherTests})
	while :; do
		[[ "${#otArray[@]}" = 0 ]] && { echo "{INFO $(date +%F_%T)} all tests submmitted."; break; }
		if [[ $vmmax -ge $((2*avg_vmcnt)) ]]; then
			echo -e "\n{INFO $(date +%F_%T)} vmmax=$vmmax(>=2*avg_vmcnt($avg_vmcnt)), submit more tests ..."
			testn=$((vmmax/avg_vmcnt))
			[[ "$testn" -gt ${#otArray[@]} ]] && testn=${#otArray[@]}
			totest=("${otArray[@]::${testn}}")
			otArray=("${otArray[@]:${testn}}")
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
fi

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
