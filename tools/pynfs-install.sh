
OSVER=$(rpm -E %rhel)

#enable epel
sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OSVER}.noarch.rpm

#install python3 and pip3
if [[ $OSVER < 8 ]]; then
	case $OSVER in
	7)
		sudo yum install -y python36 python36-pip
		;;
	6)
		sudo yum install -y python34 python34-pip
		;;
	5)
		echo "[WARN] does not support rhel-5 and before."
		;;
	esac
fi

#install module ply
yes | pip3 install ply

#git clone pynfs
sudo yum install -y git
PynfsUrl=git://git.linux-nfs.org/projects/bfields/pynfs.git
git clone $PynfsUrl
(cd pynfs; python3 ./setup.py install)
