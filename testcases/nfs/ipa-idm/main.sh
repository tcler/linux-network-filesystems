#!/bin/bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-rhel-9.?.?-????????.[0-9]+}
ipaserv=ipa-server
ipaclnt=ipa-client
password=redhat123
vm create -n $ipaserv $distro --msize 4096 -p "firewalld bind-utils expect vim" --nointeract --saveimage -f
vm cpto ipa-server /usr/bin/ipa-server-install.sh /usr/bin/kinit.sh /usr/bin/.
vm exec -v ipa-server -- systemctl start firewalld
vm exec -v ipa-server -- systemctl enable firewalld
vm exec -v ipa-server -- firewall-cmd --add-service=freeipa-ldap
vm exec -v ipa-server -- firewall-cmd --add-service=freeipa-ldaps
vm exec -v ipa-server -- firewall-cmd --add-service=http
vm exec -v ipa-server -- firewall-cmd --add-service=https
vm exec -v ipa-server -- firewall-cmd --add-service=kerberos
vm exec -v ipa-server -- firewall-cmd --add-service=dns
vm exec -v ipa-server -- firewall-cmd --add-service=freeipa-ldap --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=freeipa-ldaps --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=http --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=https --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=kerberos --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=dns --permanent
hostname=$(vm exec ipa-server -- hostname)
addr=$(vm ifaddr ipa-server)
vm exec -v ipa-server -- "echo '$addr    $hostname' >>/etc/hosts"
vm exec -v ipa-server -- dig +short $hostname A
vm exec -v ipa-server -- dig +short -x $addr

vm exec -v ipa-server -- ipa-server-install.sh
#vm exec -v ipa-server -- ipa-server-install --realm  LAB.KISSVM.ORG --ds-password $password --admin-password $password --mkhomedir --no-ntp --unattended
vm exec -v ipa-server -- ipa-server-install --realm  LAB.KISSVM.ORG --ds-password $password --admin-password $password --mkhomedir --no-ntp --unattended
vm exec -v ipa-server -- kinit.sh admin $password
vm exec -v ipa-server -- ipa pwpolicy-mod --maxlife=365
for User in li zhi cheng ben jeff steve; do
	vm exec -v ipa-server -- expect -c "spawn ipa user-add $User --first $User --last jhts --password --shell=/bin/bash
		expect {*:} {send \"$password\\r\"}
		expect {*:} {send \"$password\\r\"}
		expect eof"
	vm exec -v ipa-server -- ipa user-mod $User --password-expiration='2049-10-01 00:00:00Z'
done
vm exec -v ipa-server -- ipa user-find

for Group in qe devel; do
	vm exec -v ipa-server -- "ipa group-add $Group --desc '$Group group'"
done
vm exec -v ipa-server -- ipa group-add-member qe --users={li,zhi,cheng}
vm exec -v ipa-server -- ipa group-add-member devel --users={ben,jeff,steve}

exit 0
vm create -n $ipaclnt $distro --msize 4096 -p "bind-utils expect vim" --nointeract --saveimage -f
vm cpto ipa-server /usr/bin/ipa-client-install.sh /usr/bin/kinit.sh /usr/bin/.
