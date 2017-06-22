#!/bin/bash

#################
# CONFIGURATION #
#################

OUT="ola-rpi3-git-$(date +%F-%H%M)" # DEFAULT : "ola-rpi3-git-$(date +%F-%H%M)"
BASEDIR="/home/olarpi3" # DEFAULT : "/home/olarpi3"
DEPS="make git wget zip libcppunit-dev uuid-dev pkg-config libncurses5-dev libtool autoconf automake libmicrohttpd-dev libmicrohttpd10 protobuf-compiler python-protobuf libprotobuf-dev libprotoc-dev zlib1g-dev bison flex make libftdi-dev libftdi1 libusb-1.0-0-dev liblo-dev libavahi-client-dev"
RASPBIANURL="https://downloads.raspberrypi.org/raspbian_lite_latest"

# The script must be run as root, could be sudo, but it's not so secure to allow
# a user to sudo every command.
if (( $EUID != 0 )); then
    echo "Please run as root"
fi

function wait {
    echo "Press any key to continue or CTRL-C to stop..."
    read pause
}

# configure base directory and variables
function configBaseDir {
    echo -n "Choose a base directory : [$BASEDIR] "
    read UBASEDIR
    if [ "$UBASEDIR" != "" ]; then
        BASEDIR=$UBASEDIR
        echo "using new path : $BASEDIR"
    else
        echo "Using default path : $BASEDIR"
    fi
        INSTALLDIR="$BASEDIR/build"
        DOWNLOADDIR="$BASEDIR/download"
        MOUNTPOINT="$BASEDIR/mount"
}

# update the system and download dependencies
function installDeps {
    echo -n "Checking for dependencies, your system will be updated. [C]ontinue, [S]kip : "
    read upd
    if [ "$upd" != "C" ]; then
        echo "skipping..."
    else
        echo "Upgrading system"
        apt-get -y update
        apt-get -y upgrade
        echo "Fetching dependencies"
        apt-get install $DEPS
    fi
}

# be sure we have our directories
function setupDirs {
    echo "Setting up working directories"
    mkdir -p "$BASEDIR"
    mkdir -p "$INSTALLDIR"
    mkdir -p "$DOWNLOADDIR"
    mkdir -p "$MOUNTPOINT"
}

# download Raspbian image
function downloadRaspbian {
    if [ -e "$DOWNLOADDIR/Raspbian.img" ] ; then
	echo -n "Found a Raspbian image, do you want to skip downloading? [S]kip, [D]ownload : "
        read skip
        if [ "$skip" == "S" ]; then
            echo "skipping..."
            return
        else
	    echo "Downloading latest Raspbian image"
            wget $RASPBIANURL -O $DOWNLOADDIR/Raspbian.zip
            unzip $DOWNLOADDIR/Raspbian.zip -d $DOWNLOADDIR
            mv $DOWNLOADDIR/*.img $DOWNLOADDIR/Raspbian.img
            rm -f $DOWNLOADDIR/Raspbian.zip
	fi
    else
        echo "Downloading latest Raspbian image"
        wget $RASPBIANURL -O $DOWNLOADDIR/Raspbian.zip
        unzip $DOWNLOADDIR/Raspbian.zip -d $DOWNLOADDIR
        mv $DOWNLOADDIR/*.img $DOWNLOADDIR/Raspbian.img
        rm -f $DOWNLOADDIR/Raspbian.zip
    fi
}

# setup loop device
function setupLoop {
    echo "Checking if loop module is loaded into kernel."
    if ! lsmod | grep loop &> /dev/null ; then
        echo "Module loop not found, trying to load."
        modprobe loop
    fi
    if ! lsmod | grep loop &> /dev/null ; then
        echo "Could not load module. exiting."
        exit 2
    fi
    echo "LOADED"
    echo "Getting a free loop device"
    LOOP=$(losetup -f)
    losetup $LOOP $DOWNLOADDIR/Raspbian.img
    partprobe $LOOP
}

# mount Raspbian image
function mountRaspbian {
    echo "Mounting Raspbian image"
    mount "$LOOP"p2 $MOUNTPOINT
}

# clone ola
function cloneOla {
    echo "Getting OLA"
    if [ -e $MOUNTPOINT/home/ola ] ; then
	echo "Ola repository found, pulling instead of cloning."
	cd $MOUNTPOINT/home/ola/
	git pull
    else
	cd $MOUNTPOINT/home/
	git clone https://github.com/OpenLightingProject/ola.git
    fi
}

# get cross compilation toolchain
function getToolchain {
    echo "Getting Cross compilation toolchain"
    if [ -e $BASEDIR/toolchain/tools ] ; then
        echo "Toolchain repository found, pulling instead of cloning."
        cd $BASEDIR/toolchain/tools
        git pull
    else
	mkdir -p $BASEDIR/toolchain
	cd $BASEDIR/toolchain
	git clone https://github.com/raspberrypi/tools
    fi
}

# setup cross compilation environnement
function setupToolchain {
    echo "Setting up cross compilation environnement"
    export PATH=$PATH:$BASEDIR/toolchain/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin
    mkdir -p $BASEDIR/toolchain/rootfs
    cp -r $MOUNTPOINT/lib $BASEDIR/toolchain/rootfs/
    cp -r $MOUNTPOINT/usr $BASEDIR/toolchain/rootfs/
}

# cross compile OLA with our custom toolchain
function makeOLA {
    echo "Cross compiling OLA..."
    cd $MOUNTPOINT/home/ola
    autoreconf -i
    ./configure --enable-rdm-tests --prefix $MOUNTPOINT/usr/local/bin/ --host=arm-linux-gnueabihf --build=x86_64-linux-gnu
    wait
}

# cleanup our work, set proper permissions, things like that
function cleanup {
    echo "Cleaning up..."
}

# unmount Raspbian image
function unmountRaspbian {
    echo "Unmounting Raspbian image"
    umount $MOUNTPOINT
}

# free loop device
function freeLoop {
    echo "Freeing loop device"
    losetup -d $LOOP
}

# calculate checksum
function calculateMD5 {
    echo "Calculating checksum"
    md5sum $DOWNLOADDIR/Raspbian.img > $INSTALLDIR/$OUT.md5
    wait
}

# zip image
function zipImage {
    echo "Compressing image"
    mv $DOWNLOADDIR/Raspbian.img $INSTALLDIR/$OUT.img
    cd $INSTALLDIR
    zip $OUT.zip $OUT.img $OUT.md5
    rm -f $OUT.img
    rm -f $OUT.md5
    wait
}

configBaseDir || exit 1
installDeps || exit 2
setupDirs || exit 3
downloadRaspbian || exit 4
setupLoop || exit 5
mountRaspbian || exit 6
cloneOla || exit 7
getToolchain || exit 8
setupToolchain || exit 9
makeOLA || exit 10
#cleanup || exit 11
#unmountRaspbian || exit 12
#freeLoop || exit 13
#calculateMD5 || exit 14
#zipImage || exit 15
