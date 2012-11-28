#!/bin/bash
#
# (c) Montana State University
# xen-to-kvm.sh
# Tyghe Vallard
# tgv@montana.edu
#

# General Usage
if [ $# < 1 ]
then
	echo "Usage xen-to-kvm.sh <xen disk image path> [<domain name>]"
	exit 1
fi

# Check to see if we got the domain name variable
if [ ! -z $2 ]
then
	DOMAINNAME=$2
	createxml="create-xml.sh"

	# If the domain has been defined we don't want to redefine it
	if [ ! -f /etc/libvirt/qemu/$DOMAINNAME ]
	then
		$createxml $DOMAINNAME
	else
		echo "XML file for $DOMAINNAME already defined at /etc/libvirt/qemu/$DOMAINNAME"
	fi
fi

OLDIMAGENAME=$1
NEWIMAGENAME=`echo $OLDIMAGENAME | sed 's/\.img/\.qcow2'/`

#
# Get the size of the old image in bytes
#
oldsize=`qemu-img info $OLDIMAGENAME | grep bytes | sed -e 's/^.*(\([0-9]*\) bytes)/\1/g'`
echo "Old image $OLDIMAGENAME found with size $oldsize bytes"

#
# The old size in kilobytes
#
oldsizekb=$(($oldsize / 1024))
echo "Size in Kb: $oldsizekb"

#
# The new size will include a 1G swap so add 1G to the old size
#
newsize=$(($oldsize + 1024 * 1024 * 1024 + 1))

#
# The new size in kilobytes
#
newsizekb=$(($newsize / 1024))
echo "New size in Kb with swap space: $newsizekb"
echo ""

#
# Create the new qemu image with the appropriate size
#
echo "Creating qemu raw image with name $NEWIMAGENAME and size $newsizekb"
echo "qemu-img create -f raw $NEWIMAGENAME $newsizekb"
qemu-img create -f raw $NEWIMAGENAME $newsizekb
if [ "$?" -ne "0" ]
then
	echo "Error creating qemu image"
	exit 1
fi
echo "Done."
echo ""

#
# Label the image
#
echo "Labeling the disk image with msdos"
echo "parted --script $NEWIMAGENAME mklabel msdos"
parted --script $NEWIMAGENAME mklabel msdos
if [ "$?" -ne "0" ]
then
	echo "Failed to set disk label"
	exit 1
fi
echo "Done."
echo ""

if [ "$?" -ne "0" ]
then
	echo "Failed to set disk label"
	exit 1
fi

#
# Create Primary partition
# Data partition goes from 0 to size of old disk
#
start=0
end=$(($oldsizekb / 1024))
echo "Making ext2 fs on new image. Start: $start  End: $end"
echo "parted --script $NEWIMAGENAME mkpartfs primary ext2 $start $end"
parted --script $NEWIMAGENAME mkpartfs primary ext2 $start $end
if [ "$?" -ne "0" ]
then
	echo "Failed to set data partition"
	exit 1
fi
echo "Done."
echo ""

#
# Create Swap partition
# Swap partition goes from 1 + end of data partition to the end of disk
#
start=$(($end + 1))
end=$(($newsize / 1024 / 1024 + 1))
echo "Making swap fs on new image. Start: $start  End: $end"
echo "parted --script $NEWIMAGENAME mkpartfs primary linux-swap $start $end"
parted --script $NEWIMAGENAME mkpartfs primary linux-swap $start $end
if [ "$?" -ne "0" ]
then
	echo "Failed to set swap partition"
	exit 1
fi
echo "Done."
echo ""

#
# Now we need to mount the images to create the filesystems
# Use losetup to get get the disk on a loopback device and return that device
#
lodev=`losetup -s -f $NEWIMAGENAME`
if [ "$?" -ne "0" ]
then
	echo "Failed to setup loop device"
	exit 1
fi

#
# Use kpartx to map the partitions to devices
#
kpartx -a $lodev > /dev/null
if [ "$?" -ne "0" ]
then
	echo "Failed to set mapper devices"
	exit 1
fi

#
# Get the map device name
#
mapper=$(echo $lodev | sed s-/dev/-/dev/mapper/-)
echo "Mapper path $mapper"
echo ""

#
# Make an ext3 partition on the first partition
#
echo "Making ext3 on ${mapper}p1"
mkfs.ext3 -q ${mapper}p1
if [ "$?" -ne "0" ]
then
	echo "Failed to format data partition"
	exit 1
fi
echo "Done."
echo ""

#
# Make a swap partition on the second partition
#
echo "Making swap on ${mapper}p2"
mkswap ${mapper}p2
if [ "$?" -ne "0" ]
then
	echo "Failed to format swap partition"
	exit 1
fi
echo "Done."
echo ""

#
# Get the volume id's
#
echo "Getting volume id's"
/lib/udev/vol_id --uuid ${mapper}p1 > ext3.uuid
/lib/udev/vol_id --uuid ${mapper}p2 > swap.uuid
echo "Done."
echo ""

#
# Mount old image
#
echo "Mounting xen image for data copy"
mkdir xenimage
mount -o loop $OLDIMAGENAME xenimage
if [ "$?" -ne "0" ]
then
	echo "Failed to mount $OLDIMAGE for some reason."
	exit 1
fi
echo "Done."
echo ""

#
# Mount data partition on new image
#
echo "Mounting data partition on new image for data copy"
mkdir kvmimage
mount ${mapper}p1 kvmimage
if [ "$?" -ne "0" ]
then
	echo "Failed to mount ${mapper}p1 (new image data partition) for some reason."
	exit 1
fi
echo "Done."
echo ""

#
# Copying data from xen image to kvm image and setting up new image
#
echo "Copying data..."
cp -a xenimage/* kvmimage/
echo "Moving old boot to backup at boot.premigrate"
mv kvmimage/boot kvmimage/boot.premigrate/
echo "Making new boot directory"
mkdir kvmimage/boot
echo "Copying local grub to image"
cp -a /boot/grub/ kvmimage/boot/

echo "Setting up new image..."
echo "Setting osuosl.org as repository"
perl -i -p -e 's/archive.ubuntu.com/ubuntu.osuosl.org/g;' -e 's/security.ubuntu.com/ubuntu.osuosl.org/g' kvmimage/etc/apt/sources.list
echo "Updating sources"
chroot kvmimage apt-get update
echo "Retrieving release"
release=`cat kvmimage/etc/lsb-release | grep DISTRIB_CODENAME | sed 's/DISTRIB_CODENAME=\(.*\)/\1/'`
case "$release" in
	"gutsy")
		kernel="2.6.22-15"
	;;
	"hardy")
		kernel="2.6.24-16"
	;;
	"intrepid")
		kernel="2.6.26-27-7"
	;;
	*)
		echo "Sorry I can't determine the xen vm host os. Only Gutsy, Hardy and Intrepid are supported"
	;;
esac
echo "Release kernel is $kernel"
echo "Kernel and modules"
chroot kvmimage aptitude -y install -r grub linux-image-${kernel}-server linux-image-server linux-ubuntu-modules-${kernel}-server

#
# Grub Setup
#
echo "Removing menu.lst and generating a new one"
rm kvmimage/boot/grub/menu.lst
chroot kvmimage update-grub -y

#
# Fix the tty problem that occurs?
#
echo "Fixing tty1"
perl -p -i -e 's/tty1/xvc0/g' kvmimage/etc/event.d/xvc0

#
# Modifying the menu.lst to use the disk UUID
#
UUID=$(cat ext3.uuid)
perl -i -p -e "s/\/dev\/xvda2/UUID=$UUID/g" kvmimage/boot/grub/menu.lst

#
# Create device.map
#
echo "(hd0) $NEWIMAGENAME" >> device.map
grub --device-map=device.map --batch<<EOT
root (hd0,0)
setup (hd0)
EOT

cat > kvmimage/boot/grub/device.map << EOF
(fd0)	/dev/fd0
EOF

echo "(hd0) UUID=$UUID" > kvmimage/boot/grub/device.map
chroot kvmimage grub-set-default 0

echo "Done."
echo ""

#
# Convert the disk image to qcow2
#
echo "Converting Disk image to qcow2"
umount kvmimage
mv $NEWIMAGENAME $NEWIMAGENAME.raw
echo "kpartx -d $lodev > /dev/null"
kpartx -d $lodev > /dev/null
echo "losetup -d $lodev"
losetup -d $lodev
qemu-img convert $NEWIMAGENAME.raw -O qcow2 $NEWIMAGENAME
rm $NEWIMAGENAME.raw
if [ "$?" -ne "0" ]
then
	echo "Disk image conversion failed"
fi

#
# Cleanup
#
echo "Cleaning up"
rm device.map
umount xenimage
rm ext3.uuid
rm swap.uuid
rmdir xenimage
rmdir kvmimage
echo "Done."
echo ""

echo "Done with script"
