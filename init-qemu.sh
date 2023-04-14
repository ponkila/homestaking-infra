#!/bin/bash
# deps: qemu-desktop libvirt virt-install
# desc: a simple script for converting kexecTree to qcow2
# usage: init-qemu.sh <hostname>

# ERROR Operation not supported: Cannot use direct socket mode if no URI is set
# sudo sh -c 'echo "uri_default = \"qemu:///system\"" >> /etc/libvirt/libvirt.conf'
#
# ERROR Failed to connect socket to '/var/run/libvirt/virtqemud-sock': No such file or directory
# systemctl restart libvirtd && systemctl enable libvirtd
#
# ERROR Cannot get interface MTU on 'virbr0': No such device
# sudo virsh net-create /etc/libvirt/qemu/networks/default.xml

# Args
HOSTNAME="$1"

# Paths
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
HOST_DIR="$SCRIPT_DIR/result/$HOSTNAME/"
IMG_POOL_PATH="/var/lib/libvirt/images"
#IMG_POOL_PATH="/mnt/data/da/var/lib/libvirt/images"
# if not default folder /var/lib/libvirt/images, do selinux fix:
# sudo semanage fcontext -a -t svirt_image_t "/mnt/data/images(/.*)?"
# sudo restorecon -vR /mnt/data/images

# Server random number
randomNumber=$((1 + $RANDOM % 9999))
echo "Random number $randomNumber"

# Define variables
name="$HOSTNAME"
cpucount="14"
mem="12000" # MB
disksize="60" # G
qcow2="$IMG_POOL_PATH/$name-$randomNumber.qcow2"

kernel=$(readlink -f "$HOST_DIR/initrd")
initrd=$(readlink -f "$HOST_DIR/bzImage")
kernel_args=$(sed -n '/--command-line/p' $HOST_DIR/kexec-boot | cut -d\" -f2)

# ERROR Guest name 'foobar' is already in use.
sudo virsh destroy $name >/dev/null 2>&1
sudo virsh undefine $name >/dev/null 2>&1

# Create state disk
sudo qemu-img create -f qcow2 -o preallocation=metadata $qcow2 ${disksize}G

# Create new server
sudo virt-install -n $name --vcpus $cpucount -r $mem \
  --os-variant=fedora31 --import \
  --network bridge=virbr0 \
  --disk $qcow2,format=qcow2,bus=virtio \
  --install kernel=${kernel},initrd=${initrd},kernel_args_overwrite=yes,kernel_args="${kernel_args}" \
  --noautoconsole