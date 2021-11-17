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

# download driver and install dependency
yum install lsof pciutils elfutils-libelf-devel kernel-rpm-macros python36-devel createrepo -y
yum install tk gcc-gfortran tcsh -y
wget ftp://fs-qe.usersys.redhat.com/pub/jiyin/MLNX_OFED_LINUX-4.7-3.2.9.0-rhel8.1-x86_64.tgz
tar zxf MLNX_OFED_LINUX-4.7-3.2.9.0-rhel8.1-x86_64.tgz
pushd MLNX_OFED_LINUX-4.7-3.2.9.0-rhel8.1-x86_64
	# install MLNX_OFED driver
	./mlnxofedinstall --add-kernel-support
	systemctl stop opensm
	lspci | grep Mellanox
	/etc/init.d/openibd restart
	lspci | grep Mellanox
popd

# enable SRIOV_EN and set NUM_OF_VFS
/etc/init.d/opensmd restart
mst start
mst status
#mlxconfig -d /dev/mst/mt4103_pciconf0 q
#mlxconfig -d /dev/mst/mt4103_pciconf0 set SRIOV_EN=1 NUM_OF_VFS=4

# reboot and confirm #seems no need
#reboot
#mst start; lspci | grep Mellanox; ibstat;

# module configure, and reload
systemctl stop opensm
/etc/init.d/opensmd stop
modprobe -r rpcrdma ib_srpt ib_isert
echo "options mlx4_core port_type_array=1,1 num_vfs=4 probe_vf=2" >/etc/modprobe.d/mlx4_core.conf
/etc/init.d/openibd restart
lspci | grep Mellanox
systemctl start opensm #need confirm
ip a s

# install RHEL-8.1 vm
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

vm RHEL-8.1.1-updates-20200116.1 --nointeract -p "rdma opensm infiniband-diags librdmacm-utils"
cat >pci_0000_04_00_1.xml <<EOF
<hostdev mode='subsystem' type='pci' managed='no'>
<driver name='vfio'/>
<source>
    <address domain='0x0000' bus='0x04' slot='0x00' function='0x1'/>
</source>
</hostdev>
EOF
virsh nodedev-detach pci_0000_04_00_1
virsh attach-device root-rhel-811-updates-202001161  pci_0000_04_00_1.xml

# install windows server vm
git clone https://github.com/tcler/make-windows-vm
cd make-windows-vm
./make-win-vm.sh --image /var/lib/libvirt/images/Win2019-Evaluation.iso     --os-variant win2k19 --vmname win2019-cifs-nfs --domain cifs-nfs.test -p ~Ocgxyz     --cpus 4 --ram 4096 --disk-size 60 --vncport 7799  ./answerfiles-cifs-nfs/* --enable-kdc
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
# download windows driver
# ref: https://cn.mellanox.com/products/adapter-software/ethernet/windows/winof-2
# ref: http://www.mellanox.com/downloads/WinOF/MLNX_VPI_WinOF-5_50_52000_All_win2019_x64.exe


# guest:
: <<EOF
rdma opensm infiniband-diags librdmacm-utils
echo "SVCRDMA_LOAD=yes" >>/etc/rdma/rdma.conf  #for nfs server
modprobe svcrdma
systemctl start rdma
systemctl start opensm
lspci
ibstat
ip link set dev ib1 up
ip addr add 192.168.0.100/24 dev ib1
ping 192.168.0.1  #bare-metal peer address
EOF
