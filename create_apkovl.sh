#!/usr/bin/env sh

### Create a preconfigured Alpine overlay with minimal setting 
### for remote configuration:
### - eth0 with static IP address
### - DNS
### - SSH
### - Root password


PKGS="alpine-conf alpine-keys alpine-baselayout"
PKG_TMPDIR="/tmp/alpine-conf_temp"
OVL_TMPDIR="/tmp/apkovl_temp"
MIRROR="http://rsync.alpinelinux.org"

cleanup() {
	rm -rf $PKG_TMPDIR /tmp/alpine-*.apk /tmp/alpine-packages
	sudo rm -rf $OVL_TMPDIR
}

die() {
	echo An unexpected error occurred: $@
	cleanup
	exit 1
}

setup_interfaces() {
	printf "IP address for eth0 (e.g. 192.168.1.10)? "
	read ipaddress
	printf "Subnet mask for eth0 (e.g. 255.255.255.0)? "
	read subnetmask
	printf "Default gateway for eth0 (e.g. 192.168.1.1)? "
	read gateway
	mkdir -p $OVL_TMPDIR/etc/network || die
	printf "auto eth0\niface eth0 inet static\n\taddress $ipaddress\n\tnetmask $subnetmask\n\tgateway $gateway\n" > $OVL_TMPDIR/etc/network/interfaces
}

pause() {
	read "$*"
}

# Packages list
wget -q $MIRROR/alpine/edge/main/x86_64/ -O /tmp/alpine-packages.html || die wget pkglist

# prepare overlay directory
mkdir $OVL_TMPDIR || die
mkdir $PKG_TMPDIR || die

# get packages and untar utilities to build apkovl
for pkg in $PKGS; do
  pkgver=$(grep \"$pkg /tmp/alpine-packages.html | egrep -o [0-9]+\.[0-9]+[0-9.]*-r[0-9]+ | uniq) || die versions
	wget -q $MIRROR/alpine/edge/main/x86_64/${pkg}-${pkgver}.apk -O /tmp/${pkg}-${pkgver}.apk || die wget ${pkg}-${pkgver}.apk
done

tar xzf /tmp/alpine-conf*.apk -C $PKG_TMPDIR 2>/dev/null || die untar

# These are used by alpine-conf scripts
export ROOT=$OVL_TMPDIR
export PREFIX=$PKG_TMPDIR

# need to unset PREFIX in alpine-conf scripts
cd $PKG_TMPDIR || die
for script in hostname dns; do
	sed -i 's/^PREFIX=//' ./sbin/setup-$script || die unsetting prefix
done

# setup overlay directory
./sbin/setup-hostname || die
./sbin/setup-dns || die
setup_interfaces || die
printf '\nauto lo\niface lo inet loopback\n' >>$OVL_TMPDIR/etc/network/interfaces
tar xzf /tmp/alpine-keys-*.apk -C $OVL_TMPDIR 2>/dev/null || die untar
tar xzf /tmp/alpine-baselayout-*.apk -C $OVL_TMPDIR etc/shadow 2>/dev/null || die untar
mkdir -p $OVL_TMPDIR/etc/ssh || die
printf "PermitRootLogin yes\nPasswordAuthentication yes\nUsePrivilegeSeparation sandbox\nSubsystem\tsftp\t/usr/lib/ssh/sftp-server" > $OVL_TMPDIR/etc/ssh/sshd_config
sudo sed -i 's|^root.*|root:$6$y4KEXSNRaOCug3.5$4O//I2iwTbGOVx9vvoMvN.FW5vbSQ.OdTDiVaLAcugVtSjWlnK8Vo9F8gjN4n45qozBW1uy5QTq3pvqnc3SdH.:16727:0:::::|' $OVL_TMPDIR/etc/shadow || die password
for runlevel in boot default shutdown sysinit; do
	mkdir -p $OVL_TMPDIR/etc/runlevels/$runlevel
done

for initd in bootmisc hostname hwclock modules sysctl syslog networking; do
	ln -s /etc/init.d/$initd $OVL_TMPDIR/etc/runlevels/boot/$initd
done

for initd in devfs dmesg hwdrivers mdev modloop; do
	ln -s /etc/init.d/$initd $OVL_TMPDIR/etc/runlevels/sysinit/$initd
done

for initd in killprocs mount-ro savecache; do
	ln -s /etc/init.d/$initd $OVL_TMPDIR/etc/runlevels/shutdown/$initd
done

ln -s /etc/init.d/sshd $OVL_TMPDIR/etc/runlevels/default/sshd

printf 'alpine-base\nopenssh' > $OVL_TMPDIR/etc/apk/world

# build tar.gz with root permissions
cd $OVL_TMPDIR || die
HOST=$(cat $OVL_TMPDIR/etc/hostname)
echo "If you want to add additional files in apkovl, please add them in right directory under $OVL_TMPDIR"
echo "Press [Enter] key to continue..."
pause arg
sudo chown -R root.root $OVL_TMPDIR
sudo tar czf /tmp/${HOST}.apkovl.tar.gz . || die

echo "APKOVL is in /tmp/${HOST}.apkovl.tar.gz"
echo "SSH will autostart"
echo "root password is \"password\""
cleanup
