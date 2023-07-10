#!/usr/bin/env bash
# script to boot up a host using qemu
# usage: sh ./scripts/init-qemu.sh <hostname>
# deps: nix qemu

set -o pipefail
hostname=$1

# Specifications
result="./result"
mem="8192M"

# Check if argument was given
if [ $# -ne 1 ]; then
    echo "No hostname were provided."
    exit 1
fi

# Build the host
nix build .#"$hostname" || exit 1

# Get config.system.build set
build_set=$(nix eval --json .#nixosConfigurations."$hostname".config.system.build) || exit 1

# Launch QEMU based on format
case $build_set in
  *kexecTree*)
    # Get kernel args from kexec-boot script
    kernel_args=$(sed -n '/--command-line/p' "$result/kexec-boot" | cut -d\" -f2)
    # Launch QEMU
    qemu-system-x86_64 \
      -kernel "$result/bzImage" \
      -initrd "$result/initrd.zst" \
      -append "$kernel_args" -m "$mem"
    ;;
  *isoImage*)
    # Launch QEMU
    qemu-system-x86_64 \
      -cdrom "$result/iso/nixos.iso" \
      -m "$mem"
    ;;
  *)
    echo "$hostname does not have a supported format."
    exit 1
    ;;
esac

# qemu-system-aarch64 \
#   -M virt -m 8192M -cpu cortex-a53 \
#   -kernel "$result/bzImage" \
#   -initrd "$result/initrd.zst" \
#   -append "console=ttyAMA0,38400n8 rdinit=/bin/sh" \
#   -nographic
