#!/usr/bin/env bash
#

export LANG=C
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
PROG=$0; ARGS=("$@")
trap_try_again() { exec $PROG "${ARGS[@]}"; }

distro=${1:-9}; shift
nfsserv=nfs-server-rpc-truncated-auth
NFSSHARE=/nfsshare
NFSROOT=${NFSROOT}

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv; }
cleanup() { stopvms 2>/dev/null; }
trap cleanup EXIT
trap try_again SIGUSR2

#create nfs-server vm
trun vm create $distro -n $nfsserv -f -nointeract -p nfs-utils,wireshark,tmux "$@"

_test=rpc-truncated-auth-flavor
distrodir=$(gen_distro_dir_name $nfsserv ${SUFFIX}) || kill -s SIGUSR2 $$
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
  vmrunx - $nfsserv -- uname -r;
  trun -tmux=${_test}-console-$nfsserv -logf=$resdir/console-$nfsserv.log vm console $nfsserv

  vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
  vm exec -v $nfsserv -- make-nfs-server.sh --prefix=$NFSSHARE --nfsroot=$NFSROOT --no-tlshd
  servaddr=$(vm ifaddr $nfsserv|head -1)

  loopn=4096
  host=$servaddr
  host=$nfsserv
  for ((i=0; i<loopn; i++)); do
    python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.connect(('$host', 2049)); s.sendall(bytearray(b'\x80\x00\x00\x1b\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x02\x00\x01\x86\xa3\x00\x00\x00\x03\x00\x00\x00\x00DIE'));";
    port-available.sh $host || break;  #kernel crash
  done
  trun -x0 test $i -ge $loopn

  trun -x1-255 grep RI[P]: $resdir/console*.log
  stopvms
} &> >(tee $resdir/std.log)

tcnt
