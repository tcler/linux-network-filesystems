#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}; shift
nfsserv=loop-o-nfs
SCRIPT_DIR=$(dirname -- "$0")

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

#create nfs-server vm
trun vm create $distro -n $nfsserv -f -nointeract -p nfs-utils,wireshark,tmux "$@"

_test=loop-dev-over-nfs
distrodir=$(gen_distro_dir_name $nfsserv ${SUFFIX})
resdir=~/testres/${distrodir}/nfs/$_test
NFSSHARE=/nfsshare
NFSROOT=${NFSROOT}
mkdir -p $resdir
{
  vmrunx - $nfsserv -- uname -r;
  trun -tmux=${_test}-console-$nfsserv -logf=$resdir/console-$nfsserv.log vm console $nfsserv

  vm cpto -v  $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/get-if-by-ip.sh $SCRIPT_DIR/loop-dev-over-nfs.sh /usr/bin/.
  vm exec -v  $nfsserv -- make-nfs-server.sh --prefix=$NFSSHARE --nfsroot=$NFSROOT --no-tlshd
  vm exec -vx $nfsserv -- loop-dev-over-nfs.sh

  trun -x1-255 grep RI[P]: $resdir/console*.log
  stopvms
} &> >(tee $resdir/std.log)

tcnt
