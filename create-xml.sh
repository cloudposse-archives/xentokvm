#!/bin/bash
#
# (c) Montana State University 2008
# Tyghe Vallard
# tgv@montana.edu
#

#
# This script creates an xml config file for kvm
#

if [ $# -lt 1 ]
then
	echo "Usage: create-xml.sh <domainname> [<xmlpath>] [<memory>]"
	exit 1
fi

# The fqhn for the vm
DOMAINNAME=$1

# How much memory to  use for the vm
MEMORY=$3

# The template file for vm's
XMLTEMPLATE="/usr/share/ubuntu-vm-builder/templates/libvirt.tmpl"

# The type of vm we are building(KVM only right now)
VMTYPE="kvm"

# The destination path for the qcow image
DESTPATH="\/virt\/$DOMAINNAME"

# The configuration path for the vm
CONFPATH=$2

# The image name for the disk image
IMAGE="disk"

# Set default path if not given
if [ -z $CONFPATH ]
then
	CONFPATH="/etc/libvirt/qemu"
fi

# If the memory parameter was not given then default to 256Mb
if [ -z $MEMORY ]
then
	MEMORY="262144"
fi

# Random mac address
MAC="52:54:00$(hexdump -e '/1 ":%02x"' -n 3 /dev/urandom)"

sed -e 's/%VM%/'${VMTYPE}'/' -e 's/%LIBVIRTNAME%/'${DOMAINNAME}'/' -e 's/%MEM%/'${MEMORY}'/' -e 's/%MAC%/'${MAC}'/' -e 's/%.*loop%//g' -e 's/%DESTINATION%/'${DESTPATH}'/' -e 's/%img%/'${IMAGE}'/' -e 's/hd%curdisk%/hda/' $XMLTEMPLATE > "${CONFPATH}/${DOMAINNAME}.xml"
