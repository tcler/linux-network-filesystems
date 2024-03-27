#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#ipa-server,ipa-client setup test, based on kiss-vm
#test pass on CentOS-7,CentOS-{8,9}-stream,Fedora-38 and RHEL-7.9,RHEL-8.9,RHEL-9.3

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

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux=$$-nfsserv vm create -n $nfsserv $distro --msize 4096 -p bind-utils,vim,nfs-utils,NetworkManager --nointeract -I=$imgf -f "$@"
trun -tmux=$$-nfsclnt vm create -n $nfsclnt $distro --msize 4096 -p bind-utils,vim,nfs-utils,NetworkManager --nointeract -I=$imgf -f "$@"
trun                  vm create -n $ipaserv $distro --msize 4096 -p firewalld,bind-utils,expect,vim,tomcat,NetworkManager,sssd-tools,krb5-server --nointeract -I=$imgf -f "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-nfs.*-d.vm.creat[e]; do sleep 10; done

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
distrodir=$distro; [[ -n "${SUFFIX}" ]] && distrodir+=-${SUFFIX}
resdir=~/testres/$distrodir/nfs-function
mkdir -p $resdir
{
vm cpto -v $ipaserv /usr/bin/ipa-server-install.sh /usr/bin/kinit.sh /usr/bin/.
vm cpto -v $nfsserv /usr/bin/ipa-client-install.sh /usr/bin/{kinit.sh,make-nfs-server.sh} /usr/bin/.
vm cpto -v $nfsclnt /usr/bin/ipa-client-install.sh /usr/bin/kinit.sh /usr/bin/.
trun -tmux=$$-tmp1 vm exec -v $nfsserv -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-client-install.sh"
trun -tmux=$$-tmp2 vm exec -v $nfsclnt -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-client-install.sh"
trun               vm exec -v $ipaserv -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-server-install.sh"
echo "{INFO} waiting all vm exec process finished ..."
while ps axf|grep tmux.new.*$$-tmp.*-d.vm.exe[c].*.ipa-.*-install.sh; do sleep 10; done

#-------------------------------------------------------------------------------
#configure ipa-server
vm exec -v $ipaserv -- systemctl start firewalld
vm exec -v $ipaserv -- systemctl enable firewalld
vm exec -v $ipaserv -- firewall-cmd --add-service=freeipa-ldap
vm exec -v $ipaserv -- firewall-cmd --add-service=freeipa-ldaps
vm exec -v $ipaserv -- firewall-cmd --add-service=http
vm exec -v $ipaserv -- firewall-cmd --add-service=https
vm exec -v $ipaserv -- firewall-cmd --add-service=kerberos
vm exec -v $ipaserv -- firewall-cmd --add-service=dns
vm exec -v $ipaserv -- firewall-cmd --add-service=freeipa-ldap --permanent
vm exec -v $ipaserv -- firewall-cmd --add-service=freeipa-ldaps --permanent
vm exec -v $ipaserv -- firewall-cmd --add-service=http --permanent
vm exec -v $ipaserv -- firewall-cmd --add-service=https --permanent
vm exec -v $ipaserv -- firewall-cmd --add-service=kerberos --permanent
vm exec -v $ipaserv -- firewall-cmd --add-service=dns --permanent
vm exec -v $ipaserv -- firewall-cmd --reload
_hostname=$(vm exec $ipaserv -- hostname)
_ipa_serv_addr=$(vm ifaddr $ipaserv)
vm exec -v $ipaserv -- "echo '$_ipa_serv_addr    $_hostname' >>/etc/hosts"
vm exec -v $ipaserv -- dig +short $_hostname A
vm exec -v $ipaserv -- dig +short -x $_ipa_serv_addr

#vm exec -v $ipaserv -- ipa-server-install --realm  ${realm} --ds-password $password --admin-password $password \
#	--mkhomedir --no-ntp --unattended
_zone=$(echo "$addr" | awk -F. '{ for (i=NF-1; i>0; i--) printf("%s.",$i) }')in-addr.arpa.
vm exec -v $ipaserv -- ipa-server-install --realm  ${realm} --ds-password $password --admin-password $password \
	--mkhomedir --no-ntp --setup-dns --no-forwarders --unattended --auto-reverse #--reverse-zone=$_zone
vm exec -v $ipaserv -- "grep ${_ipa_serv_addr%.*} /etc/resolv.conf || echo servername ${_ipa_serv_addr%.*}.1 >>/etc/resolv.conf"
vm exec -v $ipaserv -- cat /etc/resolv.conf
vm exec -v $ipaserv -- kinit.sh admin $password
vm exec -v $ipaserv -- ipa pwpolicy-mod --maxlife=365
passwd_expiration=$(date -dnow+8years +%F\ %TZ)
for User in li zhi cheng ben jeff steve; do
	vm exec -v $ipaserv -- expect -c "spawn ipa user-add $User --first $User --last jhts --password --shell=/bin/bash {--password-expiration=$passwd_expiration}
		expect {*:} {send \"$password\\n\"}
		expect {*:} {send \"$password\\n\"}
		expect eof"
done
vm exec -v $ipaserv -- ipa user-find

for Group in qe devel; do
	vm exec -v $ipaserv -- "ipa group-add $Group --desc '$Group group'"
done
vm exec -v $ipaserv -- ipa group-add-member qe --users={li,zhi,cheng}
vm exec -v $ipaserv -- ipa group-add-member devel --users={ben,jeff,steve}
vm exec -v $ipaserv -- sssctl domain-list
vm exec -v $ipaserv -- sssctl user-show admin

NIC=$(vm exec -v $nfsserv -- nmcli -g DEVICE connection show|head -1)
#-------------------------------------------------------------------------------
#configure nfs-server to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
vm exec -v $nfsserv -- "nmcli connection modify 'System $NIC' ipv4.dns $_ipa_serv_addr; nmcli connection up 'System $NIC'"
vm exec -v $nfsserv -- sed -i -e "/${_ipa_serv_addr%.*}/d" -e "s/^search.*/&\nnameserver ${_ipa_serv_addr}\nnameserver ${_ipa_serv_addr%.*}.1/" /etc/resolv.conf
vm exec -v $nfsserv -- cat /etc/resolv.conf

vm exec -v $nfsserv -- dig +short SRV _ldap._tcp.$dnsdomain
vm exec -v $nfsserv -- dig +short SRV _kerberos._tcp.$dnsdomain
vm exec -v $nfsserv -- ipa-client-install --domain=$domain --realm=${realm} --principal=admin --password=$password \
	--unattended --mkhomedir
vm exec -v $nfsserv -- kinit.sh admin $password
vm exec -v $nfsserv -- klist
vm exec -vx $ipaserv -- grep $nfsserv /var/log/krb5kdc.log
vm exec -v $ipaserv -- "journalctl -u named-pkcs11.service | grep ${nfsserv}.*updating"
vm exec -v $nfsserv -- 'ipa host-show $(hostname)'

#-------------------------------------------------------------------------------
#configure nfs-client to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
vm exec -v $nfsclnt -- "nmcli connection modify 'System $NIC' ipv4.dns $_ipa_serv_addr; nmcli connection up 'System $NIC'"
vm exec -v $nfsclnt -- cat /etc/resolv.conf
vm exec -v $nfsclnt -- sed -i -e "/${_ipa_serv_addr%.*}/d" -e "s/^search.*/&\nnameserver ${_ipa_serv_addr}\nnameserver ${_ipa_serv_addr%.*}.1/" /etc/resolv.conf
vm exec -v $nfsclnt -- cat /etc/resolv.conf

vm exec -v $nfsclnt -- dig +short SRV _ldap._tcp.$dnsdomain
vm exec -v $nfsclnt -- dig +short SRV _kerberos._tcp.$dnsdomain
vm exec -v $nfsclnt -- ipa-client-install --domain=$domain --realm=${realm} --principal=admin --password=$password \
	--unattended --mkhomedir #--server=$ipaserv.$domain
vm exec -v $nfsclnt -- kinit.sh admin $password
vm exec -v $nfsclnt -- klist

vm exec -v $nfsclnt -- 'ipa host-show $(hostname)'
vm exec -v $nfsclnt -- 'command -v authselect && { authselect list; }'
vm exec -v $nfsclnt -- 'command -v authselect && { authselect show sssd; }'
vm exec -v $nfsclnt -- 'command -v authselect && { authselect test -a sssd with-mkhomedir with-sudo; }'

#-------------------------------------------------------------------------------
#nfs-server: configure krb5 nfs server
vm exec -v $nfsserv -- make-nfs-server.sh --no-tlshd
vm exec -vx $nfsserv -- "chown :qe /nfsshare/qe; chown :devel /nfsshare/devel"
vm exec -vx $nfsserv -- chmod g+ws /nfsshare/qe /nfsshare/devel
vm exec -v $nfsserv -- ls -l /nfsshare

vm exec -v $nfsserv -- ipa service-add nfs/${nfsserv}.${domain}
vm exec -v $nfsserv -- ipa-getkeytab -s ${ipaserv}.${domain} -p nfs/${nfsserv}.${domain} -k /etc/krb5.keytab
vm exec -v $ipaserv -- kadmin.local list_principals
vm exec -v $nfsserv -- klist

#-------------------------------------------------------------------------------
#nfs-client: configure krb5 nfs client
vm exec -v $nfsclnt -- mkdir /mnt/nfsmp
vm exec -v $nfsclnt -- systemctl restart nfs-client.target gssproxy.service rpc-statd.service rpc-gssd.service
vm exec -v $ipaserv -- kadmin.local list_principals
vm exec -v $nfsclnt -- klist

### __main__ test start
#-------------------------------------------------------------------------------
#simple nfs mount/umount test
vm exec -vx $nfsclnt -- showmount -e ${nfsserv}
vm exec -vx $nfsclnt -- mount ${nfsserv}:/ /mnt/nfsmp
vm exec -vx $nfsclnt -- mount -t nfs4
vm exec -vx $nfsclnt -- umount -a -t nfs4

#-------------------------------------------------------------------------------
#simple krb5 nfs mount/umount test
vm exec -vx $nfsclnt -- mount -osec=krb5 ${nfsserv}.${domain}:/nfsshare/qe /mnt/nfsmp
vm exec -vx $nfsclnt -- mount -t nfs4
vm exec -vx $nfsclnt -- umount -a -t nfs4

} |& tee $resdir/ipa-idm-nfs.log

vm stop $ipaserv $nfsserv $nfsclnt
