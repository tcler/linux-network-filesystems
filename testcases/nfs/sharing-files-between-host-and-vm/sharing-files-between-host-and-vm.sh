#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
switchroot "$@"

#export share dir by nfs
_USER=root
[[ -n "$SUDO_USER" ]] && _USER=$SUDO_USER
trun hostip=$(vm netinfo default | sed -rn "/.*ip.address='(([0-9]+\.){3}[0-9]+)'.*/{s//\1/;p}")
trun netaddr=${hostip%.*}.0/24
trun expdir=~$_USER/sharedir
trun -as=$_USER mkdir -p $expdir
trun -as=$_USER touch $expdir/testfile{1..3}
trun "echo '$expdir $netaddr(rw,sync,insecure,all_squash,anonuid=$(id -u $_USER),anongid=$(id -g $_USER))' >/etc/exports;
	systemctl restart nfs-server;"
trun 'firewall-cmd --permanent --add-service={mountd,nfs,rpc-bind};
	firewall-cmd --permanent --add-service={mountd,nfs,rpc-bind} --zone=libvirt;
	firewall-cmd --reload; '

#create windows vm
win_iso_url=http://download.devel.redhat.com/qa/rhts/lookaside/windows-images/Win2022-Evaluation.iso
vmname=win-vm
trun vm create -f Windows-server-2022 -n $vmname -C $win_iso_url \
	--osv win2k22 \
	--vcpus sockets=1,cores=4 --msize 8192 --dsize 80 \
	--win-run='Install-WindowsFeature NFS-Client' \
	--win-run='Enable-WindowsOptionalFeature -FeatureName ServicesForNFS-ClientOnly, ClientForNFS-Infrastructure -Online -NoRestart' \
	--win-run-post="showmount.exe -e ${hostip}" \
	--win-auto=base \
	--wait
trun sed -n '/autorun-post/,/autorun-post.end/p'  /tmp/${vmname}-data/postinstall.log

trun -as=$_USER vm exec -v $vmname -- 'showmount.exe -e '"${hostip}"
trun -as=$_USER vm exec -v $vmname -- 'powershell -command "mount.exe -o anon \\'"${hostip}"'\'"${expdir#/}"' Z:; ls Z:;
	if (Test-Path -Path Z:\windir) { Remove-Item -Force -Recurse Z:\windir };
	if (Test-Path -Path Z:\win.txt) { Remove-Item -Force Z:\win.txt };
	Set-Content Z:\win.txt "in.windows"; New-Item Z:\windir -ItemType "directory";
	Get-Content Z:\win.txt; ls Z:"'
