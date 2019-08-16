#!/bin/bash
# author: Jianhong Yin <yin-jianhong@163.com>
# configure samba service and start

export LANG=C

## global var
GROUP=MYGROUP
PREFIX=/smbshare
USERLIST=smbuser1,smbuser2
PASSWORD=redhat


## argparse
P=${0##*/}
Usage() {
	echo "Usage: $P [options]"
	cat <<EOF
Options:
    -h, -help              ; show this help
    -group <group name>    ; group name
    -users <user list>     ; comma separated samba user list(default: root,smbuser1,smbuser2)
    -passwd <passwd>       ; common password(default: redhat)
    -prefix <path>         ; root directory of samba share(default: /smbshare/)
EOF
}
_at=$(getopt -a -o h \
	--long help \
	--long group: \
	--long prefix: \
	--long users: \
	--long passwd: \
	-n "$P" -- "$@")
eval set -- "$_at"
while true; do
	case "$1" in
	-h|--help)    Usage; shift 1; exit 0;;
	--group)      GROUP=$2; shift 2;;
	--prefix)     PREFIX=$2; shift 2;;
	--users)      USERLIST=$2; shift 2;;
	--passwd)     PASSWORD=$2; shift 2;;
	--) shift; break;;
	esac
done


## install related packages
yum install -y samba samba-common-tools >/dev/null
yum install -y samba-client cifs-utils tree >/dev/null


## create smbusers and directorys
HOMEDIR=$PREFIX/homes
for user in ${USERLIST//,/ }; do
	useradd $user
	echo $PASSWORD | passwd --stdin $user
	echo -e "$PASSWORD\n$PASSWORD" | smbpasswd -a -s $user

	homedir=$HOMEDIR/$user
	mkdir -vp $homedir
	chown $user $homedir
	chmod go-rwx $homedir
done

echo -e "$PASSWORD\n$PASSWORD" | smbpasswd -a -s root
mkdir -vp $PREFIX/{pub,upload}
chmod a+w $PREFIX/{pub,upload}
mkdir -vp $PREFIX/share
chcon -R -t samba_share_t $PREFIX


## generate smb config file
cat <<EOF >/etc/samba/smb.conf
[global]
    workgroup = $GROUP
    server string = Samba Server Version %v
   
    log file = /var/log/samba/log.%m
    max log size = 50
    security = user
    ntlm auth = yes

[homes]
    path = $HOMEDIR/%S
    public = no
    writable = yes
    readable = yes
    printable = no
    guest ok = no
    valid users = %S

[pub]
    path = $PREFIX/pub
    writable = yes

[upload]
    path = $PREFIX/upload
    writable = yes

[share]
    path = $PREFIX/share
    writeable = no
EOF


## start samba service
service smb restart

## test/verify
smbclient -L //localhost -U root%redhat
echo
tree $PREFIX
