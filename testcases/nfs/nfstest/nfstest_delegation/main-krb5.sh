#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}

dnsdomain=lab.kissvm.net
domain=${dnsdomain}
realm=${domain^^}
ipaserv=ipa-server
nfsserv=nfs-server
nfsclntx=nfs-clientx
nfsclnt=nfs-client
password=redhat123

### download vm image
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

### __prepare__ test env build: create vm
trun -tmux vm create -n $ipaserv  $distro --msize 4096 -p vim,bind-utils,firewalld,expect,tomcat,NetworkManager,sssd-tools --nointeract -I=$imgf -f "$@"
trun -tmux vm create -n $nfsserv  $distro --msize 4096 -p vim,nfs-utils,bind-utils,NetworkManager --nointeract -I=$imgf -f --kdump "$@"
trun -tmux vm create -n $nfsclntx $distro --msize 4096 -p vim,nfs-utils,bind-utils,NetworkManager,python3 --nointeract -I=$imgf -f --kdump "$@"
trun       vm create -n $nfsclnt $distro --msize 4096 -p vim,nfs-utils,bind-utils,NetworkManager,expect,iproute-tc,kernel-modules-extra --nointeract -I=$imgf -f --kdump "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*-d.vm.creat[e]; do sleep 10; done

### __prepare__ test env build: install requirements: ipa-server/ipa-client
vm cpto $ipaserv  /usr/bin/ipa-server-install.sh /usr/bin/kinit.sh /usr/bin/.
vm cpto $nfsserv  /usr/bin/ipa-client-install.sh /usr/bin/{kinit.sh,make-nfs-server.sh} /usr/bin/.
vm cpto $nfsclnt  /usr/bin/ipa-client-install.sh /usr/bin/{kinit.sh,ssh-copy-id.sh} /usr/bin/.
vm cpto $nfsclntx /usr/bin/ipa-client-install.sh /usr/bin/{kinit.sh,ssh-copy-id.sh} /usr/bin/.

trun -tmux vm exec -v $nfsserv -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-client-install.sh"
trun -tmux vm exec -v $nfsclnt -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-client-install.sh"
trun -tmux vm exec -v $nfsclntx -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-client-install.sh"
trun       vm exec -v $ipaserv -- "systemctl enable NetworkManager; systemctl start NetworkManager; ipa-server-install.sh"
echo "{INFO} waiting all vm exec process finished ..."
while ps axf|grep tmux.new.*-d.vm.exe[c].*.ipa-.*-install.sh; do sleep 10; done

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
_hostname=$(vm exec $ipaserv -- hostname)
_ipa_serv_addr=$(vm ifaddr $ipaserv)
vm exec -v $ipaserv -- "echo '$_ipa_serv_addr    $_hostname' >>/etc/hosts"
vm exec -v $ipaserv -- dig +short $hostname A
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

#-------------------------------------------------------------------------------
#configure nfsserver to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
vm exec -v $nfsserv -- "nmcli connection modify 'System eth0' ipv4.dns $_ipa_serv_addr; nmcli connection up 'System eth0'"
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
vm exec -v $nfsclnt -- "nmcli connection modify 'System eth0' ipv4.dns $_ipa_serv_addr; nmcli connection up 'System eth0'"
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
vm exec -v $nfsclnt -- authselect list
vm exec -v $nfsclnt -- authselect show sssd
vm exec -v $nfsclnt -- authselect test -a sssd with-mkhomedir with-sudo

#-------------------------------------------------------------------------------
#configure nfs-clientx to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
vm exec -v $nfsclntx -- "nmcli connection modify 'System eth0' ipv4.dns $_ipa_serv_addr; nmcli connection up 'System eth0'"
vm exec -v $nfsclntx -- cat /etc/resolv.conf
vm exec -v $nfsclntx -- sed -i -e "/${_ipa_serv_addr%.*}/d" -e "s/^search.*/&\nnameserver ${_ipa_serv_addr}\nnameserver ${_ipa_serv_addr%.*}.1/" /etc/resolv.conf
vm exec -v $nfsclntx -- cat /etc/resolv.conf

vm exec -v $nfsclntx -- dig +short SRV _ldap._tcp.$dnsdomain
vm exec -v $nfsclntx -- dig +short SRV _kerberos._tcp.$dnsdomain
vm exec -v $nfsclntx -- ipa-client-install --domain=$domain --realm=${realm} --principal=admin --password=$password \
	--unattended --mkhomedir #--server=$ipaserv.$domain
vm exec -v $nfsclntx -- kinit.sh admin $password
vm exec -v $nfsclntx -- klist

vm exec -v $nfsclntx -- 'ipa host-show $(hostname)'
vm exec -v $nfsclntx -- authselect list
vm exec -v $nfsclntx -- authselect show sssd
vm exec -v $nfsclntx -- authselect test -a sssd with-mkhomedir with-sudo

#-------------------------------------------------------------------------------
#nfs-server: configure krb5 nfs server
vm exec -v $nfsserv -- make-nfs-server.sh
vm exec -vx $nfsserv -- "chown :qe /nfsshare/qe; chown :devel /nfsshare/devel"
vm exec -vx $nfsserv -- chmod g+ws /nfsshare/qe /nfsshare/devel
vm exec -v $nfsserv -- ls -l /nfsshare

vm exec -v $nfsserv -- ipa service-add nfs/${nfsserv}.${domain}
vm exec -v $nfsserv -- ipa-getkeytab -s ${ipaserv}.${domain} -p nfs/${nfsserv}.${domain} -k /etc/krb5.keytab
vm exec -v $ipaserv -- kadmin.local list_principals
vm exec -v $nfsserv -- klist

#-------------------------------------------------------------------------------
#ipa-client: configure krb5 nfs client
vm exec -v $nfsclnt -- systemctl restart nfs-client.target gssproxy.service rpc-statd.service rpc-gssd.service
vm exec -v $ipaserv -- kadmin.local list_principals
vm exec -v $nfsclnt -- klist

#-------------------------------------------------------------------------------
#ipa-clientx: configure krb5 nfs clientx
vm exec -v $nfsclntx -- systemctl restart nfs-client.target gssproxy.service rpc-statd.service rpc-gssd.service

### __main__ test start
#-------------------------------------------------------------------------------
expdir=/nfsshare/rw
NIC=eth0
servaddr=$(vm ifaddr $nfsserv)
clntxaddr=$(vm ifaddr $nfsclntx)
servfqdn=${nfsserv}.${domain}
clntxfqdn=${nfsclntx}.${domain}
vm cpto $nfsclnt /usr/bin/{install-nfstest.sh,ssh-copy-id.sh} /usr/bin/.
vm exec -vx $nfsclnt -- install-nfstest.sh
vm exec -vx $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vm exec -vx $nfsclnt -- ssh-copy-id.sh $clntxaddr root redhat

#-------------------------------------------------------------------------------
#2174870#c5
vm exec -vx $nfsclnt -- ip link set "$NIC" promisc on
vm exec -vx $nfsclnt -- tc qdisc add dev $NIC root netem delay 28ms

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
resdir=~/testres/$distro/nfstest
mkdir -p $resdir
{
  vm exec -v  $nfsclnt -- uname -r;
  vm exec -v  $nfsclnt -- nfstest_delegation --server=$servfqdn --export=$expdir --nfsversion=4.2 --sec=krb5 --nconnect 16;
} |& tee $resdir/delegation-krb5.log
