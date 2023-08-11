#!/bin/bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}
dnsdomain=lab.kissvm.net
ipaserv=ipa-server
ipaclnt=ipa-client
nfsserv=nfs-server
password=redhat123

vm create -n $ipaserv $distro --msize 4096 -p "firewalld bind-utils expect vim" --nointeract --saveimage -f
vm create -n $ipaclnt $distro --msize 4096 -p "bind-utils vim nfs-utils" --nointeract --saveimage -f
vm create -n $nfsserv $distro --msize 4096 -p "bind-utils vim nfs-utils" --nointeract --saveimage -f

#-------------------------------------------------------------------------------
#create new VM ipa-server
vm cpto $ipaserv /usr/bin/ipa-server-install.sh /usr/bin/kinit.sh /usr/bin/.
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
hostname=$(vm exec $ipaserv -- hostname)
servaddr=$(vm ifaddr $ipaserv)
vm exec -v $ipaserv -- "echo '$servaddr    $hostname' >>/etc/hosts"
vm exec -v $ipaserv -- dig +short $hostname A
vm exec -v $ipaserv -- dig +short -x $servaddr

vm exec -v $ipaserv -- ipa-server-install.sh
#vm exec -v $ipaserv -- ipa-server-install --realm  ${dnsdomain^^} --ds-password $password --admin-password $password \
#	--mkhomedir --no-ntp --unattended
_zone=$(echo "$addr" | awk -F. '{ for (i=NF-1; i>0; i--) printf("%s.",$i) }')in-addr.arpa.
vm exec -v $ipaserv -- ipa-server-install --realm  ${dnsdomain^^} --ds-password $password --admin-password $password \
	--mkhomedir --no-ntp --setup-dns --no-forwarders --unattended --auto-reverse #--reverse-zone=$_zone
vm exec -v $ipaserv -- "grep ${servaddr%.*} /etc/resolv.conf || echo servername ${servaddr%.*}.1 >>/etc/resolv.conf"
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
#create new VM ipa-nfsserver to join the realm
vm cpto $nfsserv /usr/bin/ipa-client-install.sh /usr/bin/kinit.sh /usr/bin/make-nfs-server.sh /usr/bin/.
vm exec -v $nfsserv -- ipa-client-install.sh

#Change host's DNS nameserver configuration to use the ipa/idm server.
vm exec -v $nfsserv -- "nmcli connection modify 'System eth0' ipv4.dns $servaddr; nmcli connection up 'System eth0'"
vm exec -v $nfsserv -- sed -i -e "/${servaddr%.*}/d" -e "s/^search.*/&\nnameserver ${servaddr}\nnameserver ${servaddr%.*}.1/" /etc/resolv.conf
vm exec -v $nfsserv -- cat /etc/resolv.conf

vm exec -v $nfsserv -- dig +short SRV _ldap._tcp.$dnsdomain
vm exec -v $nfsserv -- dig +short SRV _kerberos._tcp.$dnsdomain
vm exec -v $nfsserv -- ipa-client-install --domain=$dnsdomain --realm=${dnsdomain^^} --principal=admin --password=$password \
	--unattended --mkhomedir
vm exec -v $nfsserv -- kinit.sh admin $password
vm exec -v $nfsserv -- klist
vm exec -vx $ipaserv -- grep $nfsserv /var/log/krb5kdc.log
vm exec -vx $ipaserv -- "journalctl -u named-pkcs11.service | grep ${nfsserv}.*updating"
vm exec -v $nfsserv -- 'ipa host-show $(hostname)'

vm exec -v $nfsserv -- sed -i -e "/^#Domain/s/^#//;/Domain = /s/=.*/= ${dnsdomain}/" -e '/^LDAP/s//#&/' /etc/idmapd.conf
vm exec -v $nfsserv -- bash -c 'echo -e "[General]\n Verbosity = 2\n Domain = '"${dnsdomain}"'\n Local-Realms = '"${dnsdomain^^}"'" > /etc/idmapd.conf'
vm exec -v $nfsserv -- make-nfs-server.sh
vm exec -vx $nfsserv -- "chown :qe /nfsshare/qe; chown :devel /nfsshare/devel"
vm exec -vx $nfsserv -- chmod g+ws /nfsshare/qe /nfsshare/devel
vm exec -v $nfsserv -- ls -l /nfsshare

vm exec -v $nfsserv -- ipa service-add nfs/${nfsserv}.${dnsdomain}
vm exec -v $nfsserv -- ipa-getkeytab -s ${ipaserv}.${dnsdomain} -p nfs/${nfsserv}.${dnsdomain} -k /etc/krb5.keytab
vm exec -v $ipaserv -- kadmin.local list_principals

#-------------------------------------------------------------------------------
#create new VM ipa-client to join the realm
vm cpto $ipaclnt /usr/bin/ipa-client-install.sh /usr/bin/kinit.sh /usr/bin/.
vm exec -v $ipaclnt -- ipa-client-install.sh

#Change host's DNS nameserver configuration to use the ipa/idm server.
vm exec -v $ipaclnt -- "nmcli connection modify 'System eth0' ipv4.dns $servaddr; nmcli connection up 'System eth0'"
vm exec -v $ipaclnt -- cat /etc/resolv.conf
vm exec -v $ipaclnt -- sed -i -e "/${servaddr%.*}/d" -e "s/^search.*/&\nnameserver ${servaddr}\nnameserver ${servaddr%.*}.1/" /etc/resolv.conf
vm exec -v $ipaclnt -- cat /etc/resolv.conf

vm exec -v $ipaclnt -- dig +short SRV _ldap._tcp.$dnsdomain
vm exec -v $ipaclnt -- dig +short SRV _kerberos._tcp.$dnsdomain
vm exec -v $ipaclnt -- ipa-client-install --domain=$dnsdomain --realm=${dnsdomain^^} --principal=admin --password=$password \
	--unattended --mkhomedir #--server=$ipaserv.$dnsdomain
vm exec -v $ipaclnt -- kinit.sh admin $password
vm exec -v $ipaclnt -- klist

vm exec -v $ipaclnt -- 'ipa host-show $(hostname)'
vm exec -v $ipaclnt -- authselect list
vm exec -v $ipaclnt -- authselect show sssd
vm exec -v $ipaclnt -- authselect test -a sssd with-mkhomedir with-sudo

vm exec -v $ipaclnt -- mkdir /mnt/nfsmp
vm exec -v $ipaclnt -- sed -i -e "/^#Domain/s/^#//;/Domain = /s/=.*/= ${dnsdomain}/" -e '/^LDAP/s//#&/' /etc/idmapd.conf
vm exec -v $ipaclnt -- bash -c 'echo -e "[General]\n Verbosity = 2\n Domain = '"${dnsdomain}"'\n Local-Realms = '"${dnsdomain^^}"'" > /etc/idmapd.conf'
vm exec -v $ipaclnt -- systemctl restart nfs-client.target gssproxy.service rpc-statd.service rpc-gssd.service

#-------------------------------------------------------------------------------
vm exec -v $ipaserv -- kadmin.local list_principals
vm exec -vx $ipaclnt -- showmount -e ${nfsserv}
vm exec -vx $ipaclnt -- mount ${nfsserv}:/ /mnt/nfsmp
vm exec -vx $ipaclnt -- mount -t nfs4
vm exec -vx $ipaclnt -- umount -a -t nfs4

#-------------------------------------------------------------------------------
vm exec -v $nfsserv -- klist
vm exec -v $ipaclnt -- klist

vm exec -vx $ipaclnt -- mount -osec=krb5 ${nfsserv}:/nfsshare/qe /mnt/nfsmp
vm exec -vx $ipaclnt -- mount -t nfs4
vm exec -vx $ipaclnt -- umount -a -t nfs4
