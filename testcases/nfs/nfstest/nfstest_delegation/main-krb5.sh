#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}

dnsdomain=lab.kissvm.net
domain=${dnsdomain}
realm=${domain^^}
ipaserv=nfstest-deleg-ipa-serv
nfsserv=nfstest-deleg-nfs-serv
nfsclnt=nfstest-deleg-nfs-clnt
nfsclntx=nfstest-deleg-nfs-clntx
password=redhat123

### download vm image
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

### __prepare__ test env build: create vm
trun -tmux vm create -n $ipaserv  $distro --msize 4096 -p vim,tcpdump,bind-utils,firewalld,expect,tomcat,NetworkManager,sssd-tools --nointeract -I=$imgf -f "$@"
trun -tmux vm create -n $nfsserv  $distro --msize 4096 -p vim,tcpdump,nfs-utils,bind-utils,NetworkManager --nointeract -I=$imgf -f --kdump "$@"
trun -tmux vm create -n $nfsclntx $distro --msize 4096 -p vim,tcpdump,nfs-utils,bind-utils,NetworkManager,python3 --nointeract -I=$imgf -f --kdump "$@"
trun       vm create -n $nfsclnt $distro --msize 4096 -p vim,tcpdump,nfs-utils,bind-utils,NetworkManager,expect,iproute-tc,kernel-modules-extra --nointeract -I=$imgf -f --kdump "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $ipaserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

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
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.exe[c].*.ipa-.*-install.sh; do sleep 16; done

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
_ipa_serv_addr=$(vm ifaddr $ipaserv|head -1)
vmrunx - $ipaserv -- "echo '$_ipa_serv_addr    $_hostname' >>/etc/hosts"
vmrunx - $ipaserv -- dig +short $hostname A
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
#configure nfsserver to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
NIC=$(vmrunx - $nfsserv -- nmcli -g DEVICE connection show|sed -n 2p)
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
#configure nfs-clientx to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
NIC=$(vmrunx - $nfsclntx -- nmcli -g DEVICE connection show|sed -n 2p)
conn=$(vmrunx - $nfsclntx -- nmcli -g GENERAL.CONNECTION device show $NIC)
vmrunx - $nfsclntx -- "nmcli connection modify '$conn' ipv4.dns $_ipa_serv_addr; nmcli connection up '$conn'"
vmrunx - $nfsclntx -- cat /etc/resolv.conf
vmrunx - $nfsclntx -- sed -i -e "/${_ipa_serv_addr%.*}/d" -e "s/^search.*/&\nnameserver ${_ipa_serv_addr}\nnameserver ${_ipa_serv_addr%.*}.1/" /etc/resolv.conf
vmrunx - $nfsclntx -- cat /etc/resolv.conf

vmrunx - $nfsclntx -- dig +short SRV _ldap._tcp.$dnsdomain
vmrunx - $nfsclntx -- dig +short SRV _kerberos._tcp.$dnsdomain
vmrunx - $nfsclntx -- ipa-client-install --domain=$domain --realm=${realm} --principal=admin --password=$password \
	--unattended --mkhomedir #--server=$ipaserv.$domain
vmrunx - $nfsclntx -- kinit.sh admin $password
vmrunx - $nfsclntx -- klist

vmrunx - $nfsclntx -- 'ipa host-show $(hostname)'
vmrunx - $nfsclntx -- authselect list
vmrunx - $nfsclntx -- authselect show sssd
vmrunx - $nfsclntx -- authselect test -a sssd with-mkhomedir with-sudo

#-------------------------------------------------------------------------------
#configure nfs-client to join the realm
#Change host's DNS nameserver configuration to use the ipa/idm server.
NIC=$(vmrunx - $nfsclnt -- nmcli -g DEVICE connection show|sed -n 2p)
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
vmrunx - $nfsclnt -- authselect list
vmrunx - $nfsclnt -- authselect show sssd
vmrunx - $nfsclnt -- authselect test -a sssd with-mkhomedir with-sudo

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
#ipa-client: configure krb5 nfs client
vmrunx - $nfsclnt -- mkdir /mnt/nfsmp
vmrunx - $nfsclnt -- systemctl restart nfs-client.target gssproxy.service rpc-statd.service rpc-gssd.service
vmrunx - $ipaserv -- kadmin.local list_principals
vmrunx - $nfsclnt -- klist

#-------------------------------------------------------------------------------
#ipa-clientx: configure krb5 nfs clientx
vmrunx - $nfsclntx -- systemctl restart nfs-client.target gssproxy.service rpc-statd.service rpc-gssd.service

### __main__ test start
#-------------------------------------------------------------------------------
expdir=/nfsshare/rw
servaddr=$(vm ifaddr $nfsserv|head -1)
clntxaddr=$(vm ifaddr $nfsclntx|head -1)
servfqdn=${nfsserv}.${domain}
clntxfqdn=${nfsclntx}.${domain}
vm cpto $nfsclnt /usr/bin/{install-nfstest.sh,ssh-copy-id.sh,get-ip.sh} /usr/bin/.
vmrunx 0 $nfsclnt -- install-nfstest.sh
vmrunx 0 $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vmrunx 0 $nfsclnt -- ssh-copy-id.sh $servaddr root redhat
vmrunx 0 $nfsclnt -- ssh-copy-id.sh $clntxaddr root redhat

#-------------------------------------------------------------------------------
#2174870#c5
vmrunx 0 $nfsclnt -- ip link set "$NIC" promisc on
vmrunx 0 $nfsclnt -- tc qdisc add dev $NIC root netem delay 28ms
clntaddr=$(vm ifaddr $nfsclnt|head -1)

_test=delegation-krb5
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx -  $nfsclnt -- uname -r;
  trun -tmux=$_test-server.console -logpath=$resdir vm console $nfsserv
  trun -tmux=$_test-client.console -logpath=$resdir vm console $nfsclnt
  trun -tmux=$_test-clientx.console -logpath=$resdir vm console $nfsclntx
  vmrunx -  $nfsclnt -- nfstest_delegation --server=$servfqdn --export=$expdir --nfsversion=4.2 --sec=krb5 --interface=$NIC --client-ipaddr=$clntaddr --nconnect 16 $TESTS;
  trun -x1-255 grep RI[P]: $resdir/*console.log
} |& tee $resdir/std.log

[[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $ipaserv $nfsserv $nfsclnt $nfsclntx
