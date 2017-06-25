#!/bin/bash

RASPBIANURL="https://downloads.raspberrypi.org/raspbian_lite_latest"

# configure variables
function configVars {
    WORKINGDIR=$(pwd)
    BASEDIR="$WORKINGDIR"
    OUT="ola-rpi3-git-$(date +%F-%H%M)"
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
    echo -n "Choose an output name : [$OUT] "
    read UOUT
    if [ "$UOUT" != "" ]; then
        OUT=$UOUT
        echo "using new output name : $OUT"
    else
        echo "Using default output name : $OUT"
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
    mount "$LOOP"p1 $MOUNTPOINT/boot/
}

# clone ola
function cloneOla {
    echo "Getting OLA"
    if [ -e $MOUNTPOINT/home/ola/ola ] ; then
	echo "Ola repository found, pulling instead of cloning."
	cd $MOUNTPOINT/home/ola/ola
	git pull
    else
	mkdir -p $MOUNTPOINT/home/ola
	cd $MOUNTPOINT/home/ola
	git clone https://github.com/OpenLightingProject/ola.git
    fi
}

# cleanup our work, set proper permissions, copy tools, things like that
function setupImage {
    echo "Setting up image..."
    cd $WORKINGDIR
    cp -r files/etc $MOUNTPOINT/
    cp -r files/home $MOUNTPOINT/
    cp config.patch $MOUNTPOINT/boot/
    cp rc.local.final $MOUNTPOINT/etc/
    cp olad.service $MOUNPOINT/etc/systemd/system/
}

# apply different patches to boot/config.txt and etc/rc.local
function applyPatches {
    cd $WORKINGDIR
    patch $MOUNTPOINT/boot/config.txt < config.patch
    patch $MOUNTPOINT/etc/rc.local < rc.local.patch
}

# unmount Raspbian image
function unmountRaspbian {
    echo "Unmounting Raspbian image"
    umount $MOUNTPOINT/boot
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
    mv $DOWNLOADDIR/Raspbian.img $INSTALLDIR/$OUT.img
    cd $INSTALLDIR
    md5sum $OUT.img > $OUT.md5
}

# zip image
function zipImage {
    echo "Compressing image"
    cd $INSTALLDIR
    zip $OUT.zip $OUT.img $OUT.md5
}

# delete temporary files
function cleanup {
    rm -f $INSTALLDIR/$OUT.img
    rm -f $INSTALLDIR/$OUT.md5
}

# check if we are root
if (( $EUID != 0 )); then
    echo "Please run as root"
    exit 42
fi

# test if we have all needed tools
which wget > /dev/null 2>&1 || (echo "Please install wget" && exit 1)
which git > /dev/null 2>&1 || (echo "Please install git" && exit 1)
which zip > /dev/null 2>&1 || (echo "Please install zip" && exit 1)
which patch > /dev/null 2>&1 || (echo "Please install patch" && exit 1)
which losetup > /dev/null 2>&1 || (echo "Cannot find losetup, we need a loop device" && exit 1)

configVars || exit 2
setupDirs || exit 3
downloadRaspbian || exit 4
setupLoop || exit 5
mountRaspbian || exit 6
cloneOla || exit 7
setupImage || exit 8
applyPatches || exit 9
unmountRaspbian || exit 10
freeLoop || exit 11
calculateMD5 || exit 12
zipImage || exit 13
cleanup || exit 14
echo "Done. The image is $INSTALLDIR/$OUT.zip"
