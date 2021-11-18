#RDMA Mellanox ConnectX-3 card SR-IOV configure:
#ref: https://community.mellanox.com/s/article/howto-configure-sr-iov-for-connectx-3-with-kvm--infiniband-x  #configure sr-iov
#ref: https://community.mellanox.com/s/article/howto-install-mlnx-ofed-driver  #install ofed driver
#ref: https://cn.mellanox.com/products/infiniband-drivers/linux/mlnx_ofed  #ofed driver download page

LANG=C

# add kernel option "intel_iommu=on iommu=pt" and reboot
: <<\COMM
yum install -y grubby
grubby --args="intel_iommu=on iommu=pt" --update-kernel="$(/sbin/grubby --default-kernel)"
reboot
COMM

# install dependency and download MLNX_OFED driver
yum install -y lsof pciutils elfutils-libelf-devel \
	kernel-rpm-macros python36-devel createrepo \
	tk tcsh gcc-gfortran
wget http://fs-qe.usersys.redhat.com/ftp/pub/jiyin/MLNX_OFED_LINUX-4.9-4.0.8.0-rhel8.4-x86_64.tgz

# install MLNX_OFED driver
tar zxf MLNX_OFED_LINUX-4.9-4.0.8.0-rhel8.4-x86_64.tgz
pushd MLNX_OFED_LINUX-4.9-4.0.8.0-rhel8.4-x86_64
	./mlnxofedinstall --add-kernel-support
	lspci | grep Mellanox

	systemctl stop opensm
	/etc/init.d/opensmd stop
	modprobe -r rpcrdma ib_srpt ib_isert
	/etc/init.d/openibd restart

	lspci | grep Mellanox
	/etc/init.d/opensmd restart
popd

# only once: update firmware enable SRIOV_EN and set NUM_OF_VFS
: <<\COMM
mst start
mst status

mdevs=$(mst status | awk  '/^.dev.mst.*pciconf0/{print $1}')
mdevs=$(for mdev in $mdevs; do
	mlxconfig -d $mdev q |& awk '/Device:/{print $2}'
done)
for mdev in $mdevs; do
	mlxconfig -d $mdev set SRIOV_EN=1 NUM_OF_VFS=16
done

# reboot and confirm #seems no need
reboot
COMM

# module configure, and reload
systemctl stop opensm
/etc/init.d/opensmd stop
modprobe -r rpcrdma ib_srpt ib_isert
echo "options mlx4_core port_type_array=1,1 num_vfs=8 probe_vf=0" >/etc/modprobe.d/mlx4_core.conf
/etc/init.d/openibd restart
lspci | grep Mellanox
systemctl start opensm #need confirm
ip a s

# install kiss-vm tool
install-kiss-vm-ns() {
	local _name=$1
	local KissUrl=https://github.com/tcler/kiss-vm-ns
	which vm &>/dev/null || {
		echo -e "{info} installing kiss-vm-ns ..."
		which git &>/dev/null || yum install -y git
		while true; do
			git clone --depth=1 "$KissUrl" && make -C kiss-vm-ns
			which vm && break
			sleep 5
			echo -e "{warn} installing kiss-vm-ns  fail, try again ..."
		done
	}
	[[ "$_name"x = "vm"x ]] && vm prepare
}
install-kiss-vm-ns vm

# create RHEL-8.4 vm
vm create RHEL-8.4.0 -n rhel-8-rdma --nointeract \
	-p "rdma opensm infiniband-diags librdmacm-utils" \
	--hostdev=pci_0000_04_00_1
: <<\COMM
cat >pci_0000_04_00_1.xml <<EOF
<hostdev mode='subsystem' type='pci' managed='no'>
<driver name='vfio'/>
<source>
    <address domain='0x0000' bus='0x04' slot='0x00' function='0x1'/>
</source>
</hostdev>
EOF
virsh nodedev-detach pci_0000_04_00_1
virsh attach-device rhel-8-rdma pci_0000_04_00_1.xml
COMM

# create windows server vm
git clone https://github.com/tcler/make-windows-vm
cd make-windows-vm
./make-win-vm.sh --image /var/lib/libvirt/images/Win2019-Evaluation.iso \
	--os-variant win2k19 --vmname win2019-cifs-nfs \
	--domain cifs-nfs.test -p ~Ocgxyz \
	--cpus 4 --ram 4096 --disk-size 60 --vncport 7799 \
	--enable-kdc \
	--hostdev=pci_0000_04_00_2 \
	./answerfiles-cifs-nfs/*
: <<\COMM
cat >pci_0000_04_00_2.xml <<EOF
<hostdev mode='subsystem' type='pci' managed='no'>
<driver name='vfio'/>
<source>
    <address domain='0x0000' bus='0x04' slot='0x00' function='0x2'/>
</source>
</hostdev>
EOF
virsh nodedev-detach pci_0000_04_00_2
virsh attach-device win2019-cifs-nfs  pci_0000_04_00_2.xml
COMM
# download windows driver
# ref: https://cn.mellanox.com/products/adapter-software/ethernet/windows/winof-2
# ref: http://www.mellanox.com/downloads/WinOF/MLNX_VPI_WinOF-5_50_52000_All_win2019_x64.exe


# guest:
: <<EOF
yum install -y rdma opensm infiniband-diags librdmacm-utils
sed -i -e '/rdma/s/^#//' -e 's/rdma=n/rdma=y/' /etc/nfs.conf
systemctl start nfs-server
systemctl start opensm
lspci
ibstat
ip link set dev ib1 up
ip addr add 192.168.1.100/24 dev ib1
ping 192.168.1.1  #bare-metal peer address
EOF
