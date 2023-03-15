#!/bin/bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-rhel-9.?.?-????????.[0-9]+}
ipaserv=ipa-server
password=redhat123
vm create -n $ipaserv $distro --msize 2048 -p "firewalld bind-utils vim" --nointeract --saveimage -f
vm exec -v ipa-server -- systemctl start firewalld
vm exec -v ipa-server -- systemctl enable firewalld
vm exec -v ipa-server -- firewall-cmd --add-service=freeipa-ldap
vm exec -v ipa-server -- firewall-cmd --add-service=freeipa-ldaps
vm exec -v ipa-server -- firewall-cmd --add-service=http
vm exec -v ipa-server -- firewall-cmd --add-service=https
vm exec -v ipa-server -- firewall-cmd --add-service=kerberos
vm exec -v ipa-server -- firewall-cmd --add-service=freeipa-ldap --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=freeipa-ldaps --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=http --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=https --permanent
vm exec -v ipa-server -- firewall-cmd --add-service=kerberos --permanent
hostname=$(vm exec ipa-server -- hostname)
addr=$(vm ifaddr ipa-server)
vm exec -v ipa-server -- "echo '$addr    $hostname' >>/etc/hosts"
vm exec -v ipa-server -- dig +short $hostname A
vm exec -v ipa-server -- dig +short -x $addr

vm cpto ipa-server /usr/bin/ipa-server-install.sh .
vm exec -v ipa-server -- ./ipa-server-install.sh
vm exec -v ipa-server -- ipa-server-install --realm  LAB.KISSVM.ORG --ds-password $password --admin-password $password --no-ntp --unattended
