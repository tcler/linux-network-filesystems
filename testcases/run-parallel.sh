#!/bin/bash

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

export LANG=C
P=${0##*/}

avg_msize=4  #per VM
avg_vmcnt=2  #per test
available_ramsize() { LANG=C free -g | awk '/^Mem:/{print $NF}'; }
total_ramsize() { LANG=C free -g | awk '/^Mem:/{print $2}'; }
get_running_vms() { virsh list --state-running --name|wc -l; }
get_vcpumax() {
	local nproc=$(nproc)
	echo $((nproc*nproc/2))
}
get_now_and_max_available_vms() {
	local mempervm=${1:-4}

	local totalmem=$(total_ramsize)
	local runningvms=$(get_running_vms)
	local totalavailablevms=$((totalmem/mempervm))
	local nowavailablevms=$((totalavailablevms - runningvms))

	local availablemem=$(available_ramsize)
	local memavailablevms=$((availablemem/mempervm))
	local availablevms=$memavailablevms

	[[ $availablevms -gt $nowavailablevms ]] && availablevms=$nowavailablevms
	echo $availablevms $totalavailablevms
}

Usage() {
	echo "Usage: $P [-h] [--suffix=mr-xxx] [--no|--no-ontap] [-f <path-pattern>] <distro> [vm-create-options]";
	echo "  e.g: $P --no-ontap RHEL-8.10.0"
	echo "  e.g: $P -f ontap RHEL-9.5.0"
	echo "  e.g: $P -f nfstest.cache RHEL-10.0"
	echo "  e.g: $P --suffix RHEL-80508-mr421_1690255145 RHEL-10.0 -b https://s3.amazonaws.com/somepath/repo/6.12.0-57.421_1690255145.el10.x86_64"
}
while true; do
	case "$1" in
	-h|--help)	Usage; shift 1; exit 0;;
	-f|--filter)	pathPattern=$2; shift 2;;
	--suffix)	SUFFIX=${2}; shift 2;;
	--suffix=*)	SUFFIX=${1#*=}; shift 1;;
	--no|--noontap)	noOntap=yes; shift 1; exit 0;;
	*)		break;;
	esac
done
SUFFIX=${SUFFIX//\//.}
export SUFFIX=${SUFFIX// /_}

[[ $# -eq 0 ]] && { Usage; exit 1; }
distro=$1; shift
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog");
if [[ -n "${imgf}" ]]; then
	IOpt=-I=${imgf}
else
	echo "{ERROR} download distro: $distro fail. maybe the image has been removed from beaker" >&2
	exit 2
fi
distro=$(awk '/getting fastest location/{print $(NF-1)}' <<<"$stdlog")
[[ -z $distro ]] && { echo "{WARN} distro name is empty, exit" >&2; exit; }
tag=${distro}.${SUFFIX}
sessiontag=fsparallel-test-${tag}
_at=($distro "$@" "$IOpt")
if [[ "${_at[*]}" =~ .*-b[=\ ](repo:)?http.* ]]; then
	url=$(echo "${_at[*]}"|sed -r 's/.*-b[= ](repo:)?(http[^ ]+).*/\2/')
	yum-repo-query.sh "$url" || exit 1
fi

if ! ping -I $(get-default-if.sh) -4c 4 ipa.corp.redhat.com; then
	_at+=(--net=default --net=kissaltnet)
fi

for ts in $(tmux ls 2>/dev/null | awk -F: '/'"$sessiontag"'/ {print $1}'); do
	tmux kill-session -t ${ts};
done
for ts in $(tmux ls 2>/dev/null | awk -F: '/kissrun-/ {print $1}'); do
	tmux kill-session -t ${ts};
done

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

read avmmax vmmax < <(get_now_and_max_available_vms $avg_msize)
vcpumax=$(get_vcpumax); vcpus=$((vcpumax/vmmax))
export VCPUS=$vcpus,sockets=1,cores=$vcpus
ontap_vmmax=6

if [[ -n "${ontapTests}" ]]; then
	if [[ $avmmax -ge $ontap_vmmax ]]; then
		echo -e "{INFO $(date +%F_%T) $tag} submit ontap-simulator related test cases in background ..."
		tmux new -s ${sessiontag}/ontap/ -d bash -c "for f in ${ontapTests//$'\n'/ }; do \$f ${_at[*]}; done"
		sleep 5
		tmux ls
	else
		echo -e "\n{WARN} free memory(<$((ontap_vmmax*avg_msize))G) is not enough for ontap simulator tests ..."
		exit 75
	fi
fi

if [[ -n "${otherTests}" ]]; then
	otArray=(${otherTests})
	while :; do
		[[ "${#otArray[@]}" = 0 ]] && { echo "{INFO $(date +%F_%T) $tag} all tests submmitted."; break; }
		read avmmax _ < <(get_now_and_max_available_vms $avg_msize)
		if [[ $avmmax -ge 2 ]]; then
			echo -e "\n{INFO $(date +%F_%T) $tag} available vms $avmmax > 2, submit more tests ..."
			testn=$((avmmax/avg_vmcnt + 1))
			[[ "$testn" -gt ${#otArray[@]} ]] && testn=${#otArray[@]}
			totest=("${otArray[@]::${testn}}")
			otArray=("${otArray[@]:${testn}}")
			for f in "${totest[@]}"; do
				sessionName="${sessiontag}/${f#./}"
				echo [run] tmux new -s $sessionName -d \"$f ${_at[*]}\"
				tmux new -s "$sessionName" -d "$f ${_at[*]}"
			done
			sleep 2m
		else
			echo -e "\n{INFO $(date +%F_%T) $tag} available vms: $avmmax, waiting some tests finish ..."
			sleep 2m
		fi
	done
fi

arch=$(sed -rn '/.*--arch[= ]([^ ]+).*/{s//\1/;p}' <<<"$*")
distrodir=$(_gen_distro_dir_name $distro ${arch:-x86_64} ${SUFFIX})
resdir=~/testres/${distrodir}
while :; do
	echo -e "\n{INFO $(date +%F_%T) $tag} waiting all tests done ..."
	if tmux ls 2>/dev/null | grep $sessiontag; then
		sleep 4m;
	else
		echo -e "\n{INFO $(date +%F_%T) $tag} all tests have done, please check the results at ${resdir}"
		ls -l ${resdir}
		grep -E RIP[:] -r ${resdir}
		grep -E '(KISS.)?TEST.FAIL' -r ${resdir}
		break
	fi
done
