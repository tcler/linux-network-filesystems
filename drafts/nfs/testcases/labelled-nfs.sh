#!/bin/bash

baseurl=http://download.eng.bos.redhat.com/qa/rhts/lookaside/bkr-client-improved
baseurl=https://raw.githubusercontent.com/tcler/bkr-client-improved/master
curl -s -o /usr/local/bin/ns -L ${baseurl}/utils/ns
chmod +x /usr/local/bin/ns

ns
ns jj nsbase nfs-utils iproute iputils firewalld
ns jj nsmini bash

ns -n serv --macvlan-ip 192.168.254.1  --clone nsbase
ns exec serv -- mkdir -p /nfsshare
ns exec serv -- touch /nfsshare/testfile
ns exec serv -- 'echo "/nfsshare *(rw,no_root_squash,security_label)" >/etc/exports'
ns exec serv -- systemctl restart nfs-server
ns exec serv -- systemctl start firewalld
ns exec serv -- firewall-cmd --add-service={nfs,mountd,rpc-bind}
ns exec serv -- firewall-cmd --get-services

ns -n c1 --macvlan-ip 192.168.254.11 -bind=/usr -noboot -clone nsmini
ns exec c1 -- mkdir -p /mnt/nfs
ns exec c1 -- showmount -e 192.168.254.1
ns exec c1 -- mount 192.168.254.1:/ /mnt/nfs -overs=4.2,actimeo=1,sync
ns exec c1 -- mount -t nfs
ns exec c1 -- mount -t nfs4

ns exec serv -- ls -lZ /nfsshare/testfile
ns exec c1 -- ls -lZ /mnt/nfs/nfsshare/testfile
ns exec serv -- stat -c %C /nfsshare/testfile | tee con.s
ns exec c1 -- stat -c %C /mnt/nfs/nfsshare/testfile | tee con.c
cmp con.s con.c || echo -e "\n{warnig} ^^^^^^^^^^^"

ns exec serv -- chcon -t etc_t /nfsshare/testfile
sleep 1
ns exec serv -- ls -lZ /nfsshare/testfile
ns exec c1 -- ls -lZ /mnt/nfs/nfsshare/testfile
ns exec serv -- stat -c %C /nfsshare/testfile | tee con.s
ns exec c1 -- stat -c %C /mnt/nfs/nfsshare/testfile | tee con.c
cmp con.s con.c || echo -e "\n{warnig} ^^^^^^^^^^^"

ns exec serv -- chcon -t default_t /nfsshare/testfile
sleep 1
ns exec serv -- ls -lZ /nfsshare/testfile
ns exec c1 -- ls -lZ /mnt/nfs/nfsshare/testfile
ns exec serv -- stat -c %C /nfsshare/testfile | tee con.s
ns exec c1 -- stat -c %C /mnt/nfs/nfsshare/testfile | tee con.c
cmp con.s con.c || echo -e "\n{warnig} ^^^^^^^^^^^"

ns exec c1 -- mount -t nfs
ns exec c1 -- mount -t nfs4
