#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#ipa-server,ipa-client setup test, based on kiss-vm
#test pass on CentOS-7,CentOS-{8,9}-stream,Fedora-40 and RHEL-7.9,RHEL-8.9,RHEL-9.5

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
dnsdomain=lab.kissvm.net
domain=${dnsdomain}
realm=${domain^^}
ipaserv=ipa-server
nfsserv=ipa-nfs-server
nfsclnt=ipa-nfs-client
password=redhat123

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $ipaserv $nfsserv $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

### __prepare__ test env build: create vm
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

trun -tmux=$$-nfsserv vm create -n $nfsserv $distro --msize 4096 -p bind-utils,vim,nfs-utils,NetworkManager --nointeract -f "$@" $insOpt
trun -tmux=$$-nfsclnt vm create -n $nfsclnt $distro --msize 4096 -p bind-utils,vim,nfs-utils,NetworkManager,tmux --nointeract -f "$@" $insOpt
trun                  vm create -n $ipaserv $distro --msize 4096 -p firewalld,bind-utils,expect,vim,tomcat,NetworkManager,sssd-tools,krb5-server --nointeract -f "$@" $insOpt
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-nfs.*-d.vm.creat[e]; do sleep 10; done
timeout 300 vm port-available -w $nfsserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

read nfsservaddr < <(vm ifaddr $nfsserv)
read nfsclntaddr < <(vm ifaddr $nfsclnt|grep ${nfsservaddr%.*})

_test=xfstests-nfs-ipa-krb5
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
trun -tmux=${_test}-console-$ipaserv -logf=$resdir/console-$ipaserv.log vm console $ipaserv
trun -tmux=${_test}-console-$nfsserv -logf=$resdir/console-$nfsserv.log vm console $nfsserv
trun -tmux=${_test}-console-$nfsclnt -logf=$resdir/console-$nfsclnt.log vm console $nfsclnt

### __prepare__ test env build: install requirements: ipa-server/ipa-client
vm cpto -v $ipaserv /usr/bin/ipa-server-install.sh /usr/bin/kinit.sh /usr/bin/.
vm cpto -v $nfsserv /usr/bin/ipa-client-install.sh /usr/bin/{kinit.sh,make-nfs-server.sh,get-if-by-ip.sh} /usr/bin/.
vm cpto -v $nfsclnt /usr/bin/ipa-client-install.sh /usr/bin/{kinit.sh,get-if-by-ip.sh} /usr/bin/.

trun -tmux=$$-tmp1 vm exec -v $nfsserv -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-client-install.sh"
trun -tmux=$$-tmp2 vm exec -v $nfsclnt -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-client-install.sh"
trun               vm exec -v $ipaserv -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-server-install.sh"
echo "{INFO} waiting all vm exec process finished ..."
while ps axf|grep tmux.new.*$$-tmp.*-d.vm.exe[c].*.ipa-.*-install.sh; do sleep 10; done

#-------------------------------------------------------------------------------
#configure ipa-server
vmrunx - $ipaserv -- systemctl start firewalld
vmrunx - $ipaserv -- systemctl enable firewalld
vmrunx - $ipaserv -- firewall-cmd --add-service=freeipa-ldap
vmrunx - $ipaserv -- firewall-cmd --add-service=freeipa-ldaps
vmrunx - $ipaserv -- firewall-cmd --add-service=http
vmrunx - $ipaserv -- firewall-cmd --add-service=https
vmrunx - $ipaserv -- firewall-cmd --add-service=kerberos
vmrunx - $ipaserv -- firewall-cmd --add-service=dns
vmrunx - $ipaserv -- firewall-cmd --add-service=freeipa-ldap --permanent
vmrunx - $ipaserv -- firewall-cmd --add-service=freeipa-ldaps --permanent
vmrunx - $ipaserv -- firewall-cmd --add-service=http --permanent
vmrunx - $ipaserv -- firewall-cmd --add-service=https --permanent
vmrunx - $ipaserv -- firewall-cmd --add-service=kerberos --permanent
vmrunx - $ipaserv -- firewall-cmd --add-service=dns --permanent
vmrunx - $ipaserv -- firewall-cmd --reload
_hostname=$(vm exec $ipaserv -- hostname)
read _ipa_serv_addr < <(vm ifaddr $ipaserv|grep ${nfsservaddr%.*})
vmrunx - $ipaserv -- "echo '$_ipa_serv_addr    $_hostname' >>/etc/hosts"
vmrunx - $ipaserv -- dig +short $_hostname A
vmrunx - $ipaserv -- dig +short -x $_ipa_serv_addr

#vmrunx - $ipaserv -- ipa-server-install --realm  ${realm} --ds-password $password --admin-password $password \
#	--mkhomedir --no-ntp --unattended
_zone=$(echo "$addr" | awk -F. '{ for (i=NF-1; i>0; i--) printf("%s.",$i) }')in-addr.arpa.
vmrunx - $ipaserv -- ipa-server-install --realm  ${realm} --ds-password $password --admin-password $password \
	--mkhomedir --no-ntp --setup-dns --no-forwarders --unattended --auto-reverse #--reverse-zone=$_zone
vmrunx - $ipaserv -- "grep ${_ipa_serv_addr%.*} /etc/resolv.conf || echo servername ${_ipa_serv_addr%.*}.1 >>/etc/resolv.conf"
vmrunx - $ipaserv -- cat /etc/resolv.conf
vmrunx - $ipaserv -- kinit.sh admin $password
vmrunx - $ipaserv -- ipa pwpolicy-mod --maxlife=365
passwd_expiration=$(date -dnow+8years +%F\ %TZ)
for User in li zhi cheng ben jeff steve; do
	vmrunx - $ipaserv -- expect -c "spawn ipa user-add $User --first $User --last jhts --password --shell=/bin/bash {--password-expiration=$passwd_expiration}
		expect {*:} {send \"$password\\n\"}
		expect {*:} {send \"$password\\n\"}
		expect eof"
done
vmrunx - $ipaserv -- ipa user-find

for Group in qe devel; do
	vmrunx - $ipaserv -- "ipa group-add $Group --desc '$Group group'"
done
vmrunx - $ipaserv -- ipa group-add-member qe --users={li,zhi,cheng}
vmrunx - $ipaserv -- ipa group-add-member devel --users={ben,jeff,steve}
vmrunx - $ipaserv -- sssctl domain-list
vmrunx - $ipaserv -- sssctl user-show admin

#-------------------------------------------------------------------------------
#configure nfs-server to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
NIC=$(vmrunx - $nfsserv -- get-if-by-ip.sh $nfsservaddr)
conn=$(vmrunx - $nfsserv -- nmcli -g GENERAL.CONNECTION device show $NIC)
vmrunx - $nfsserv -- "nmcli connection modify '$conn' ipv4.dns $_ipa_serv_addr; nmcli connection up '$conn'"
vmrunx - $nfsserv -- sed -i -e "/${_ipa_serv_addr%.*}/d" -e "s/^search.*/&\nnameserver ${_ipa_serv_addr}\nnameserver ${_ipa_serv_addr%.*}.1/" /etc/resolv.conf
vmrunx - $nfsserv -- cat /etc/resolv.conf

vmrunx - $nfsserv -- dig +short SRV _ldap._tcp.$dnsdomain
vmrunx - $nfsserv -- dig +short SRV _kerberos._tcp.$dnsdomain
vmrunx - $nfsserv -- ipa-client-install --domain=$domain --realm=${realm} --principal=admin --password=$password \
	--unattended --mkhomedir
vmrunx - $nfsserv -- kinit.sh admin $password
vmrunx - $nfsserv -- klist
vmrunx 0 $ipaserv -- grep $nfsserv /var/log/krb5kdc.log
vmrunx - $ipaserv -- "journalctl -u named-pkcs11.service | grep ${nfsserv}.*updating"
vmrunx - $nfsserv -- 'ipa host-show $(hostname)'

#-------------------------------------------------------------------------------
#configure nfs-client to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
NIC=$(vmrunx - $nfsclnt -- get-if-by-ip.sh $nfsclntaddr)
conn=$(vmrunx - $nfsclnt -- nmcli -g GENERAL.CONNECTION device show $NIC)
vmrunx - $nfsclnt -- "nmcli connection modify '$conn' ipv4.dns $_ipa_serv_addr; nmcli connection up '$conn'"
vmrunx - $nfsclnt -- cat /etc/resolv.conf
vmrunx - $nfsclnt -- sed -i -e "/${_ipa_serv_addr%.*}/d" -e "s/^search.*/&\nnameserver ${_ipa_serv_addr}\nnameserver ${_ipa_serv_addr%.*}.1/" /etc/resolv.conf
vmrunx - $nfsclnt -- cat /etc/resolv.conf

vmrunx - $nfsclnt -- dig +short SRV _ldap._tcp.$dnsdomain
vmrunx - $nfsclnt -- dig +short SRV _kerberos._tcp.$dnsdomain
vmrunx - $nfsclnt -- ipa-client-install --domain=$domain --realm=${realm} --principal=admin --password=$password \
	--unattended --mkhomedir #--server=$ipaserv.$domain
vmrunx - $nfsclnt -- kinit.sh admin $password
vmrunx - $nfsclnt -- klist

vmrunx - $nfsclnt -- 'ipa host-show $(hostname)'
vmrunx - $nfsclnt -- 'command -v authselect && { authselect list; }'
vmrunx - $nfsclnt -- 'command -v authselect && { authselect show sssd; }'
vmrunx - $nfsclnt -- 'command -v authselect && { authselect test -a sssd with-mkhomedir with-sudo; }'

#-------------------------------------------------------------------------------
#nfs-server: configure krb5 nfs server
vmrunx - $nfsserv -- make-nfs-server.sh --no-tlshd
vmrunx 0 $nfsserv -- "chown :qe /nfsshare/qe; chown :devel /nfsshare/devel"
vmrunx 0 $nfsserv -- chmod g+ws /nfsshare/qe /nfsshare/devel
vmrunx - $nfsserv -- ls -l /nfsshare

vmrunx - $nfsserv -- ipa service-add nfs/${nfsserv}.${domain}
vmrunx - $nfsserv -- ipa-getkeytab -s ${ipaserv}.${domain} -p nfs/${nfsserv}.${domain} -k /etc/krb5.keytab
vmrunx - $ipaserv -- kadmin.local list_principals
vmrunx - $nfsserv -- klist

#-------------------------------------------------------------------------------
#nfs-client: configure krb5 nfs client
vmrunx - $nfsclnt -- mkdir /mnt/nfsmp
vmrunx - $nfsclnt -- systemctl restart nfs-client.target gssproxy.service rpc-statd.service rpc-gssd.service
vmrunx - $ipaserv -- kadmin.local list_principals
vmrunx - $nfsclnt -- klist

### __main__ test start
#-------------------------------------------------------------------------------
#simple nfs mount/umount test
vmrunx 0 $nfsclnt -- showmount -e ${nfsserv}
vmrunx 0 $nfsclnt -- mount ${nfsserv}:/ /mnt/nfsmp
vmrunx 0 $nfsclnt -- mount -t nfs4
vmrunx 0 $nfsclnt -- umount -a -t nfs4

#-------------------------------------------------------------------------------
#simple krb5 nfs mount/umount test
vmrunx 0 $nfsclnt -- mount -osec=krb5 ${nfsserv}.${domain}:/nfsshare/qe /mnt/nfsmp
vmrunx 0 $nfsclnt -- mount -t nfs4
vmrunx 0 $nfsclnt -- umount -a -t nfs4

#-------------------------------------------------------------------------------
vm cpto -v  $nfsclnt /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vmrunx 0 $nfsclnt -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils'
vmrunx 0 $nfsclnt -- "xfstests-install.sh nouring=$NOURING" || exit 1
vmrunx 0 $nfsclnt -- showmount -e $nfsservaddr

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vmrunx - $nfsclnt -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vmrunx - $nfsclnt -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
vmrunx - $nfsclnt -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=${nfsserv}.${domain}:/nfsshare/qe
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=${nfsserv}.${domain}:/nfsshare/devel
export SCRATCH_MNT=/mnt/xfstests_scratch
export WORKAREA=/var/lib/xfstests
export MOUNT_OPTIONS='-o sec=krb5'
EOF"

vmrunx - $nfsclnt -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check -nfs ${TESTS:--g quick};"

trun -x1-255 grep RI[P]: $resdir/console*.log
stopvms
} &> >(tee $resdir/std.log)

tcnt
