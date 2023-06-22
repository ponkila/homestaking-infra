#!/usr/bin/env bash
# script to boot up a host using qemu
# usage: sh ./scripts/init-qemu.sh <hostname>
# deps: nix qemu

set -o pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
hostname=$1

# Check if argument was given
if [ $# -ne 1 ]; then
    echo "No hostname were provided."
    exit 1
fi

# Check if QEMU is installed
if ! command -v qemu-system-x86_64 &>/dev/null; then
    echo "qemu-system-x86_64: command not found. Please install QEMU."
    exit 1
fi

# Check if the provided hostname exists
if [ ! -d "$script_dir/../hosts/$hostname" ]; then
  echo "$hostname does not exist."
  exit 1
fi

# Check if the host uses the kexecTree format
if [[ -z $(nix eval --json .#nixosConfigurations."$hostname".config.system.build.kexecTree 2>/dev/null) ]]; then
    echo "$hostname does not use the kexecTree format."
    exit 1
fi

# Build the host
nix build .#"$hostname" || exit 1

# Get kernel args from kexec-boot script
kernel_args=$(sed -n '/--command-line/p' "$script_dir/../result/kexec-boot" | cut -d\" -f2)

# Launch QEMU
qemu-system-x86_64 \
  -kernel "$script_dir/../result/bzImage" \
  -initrd "$script_dir/../result/initrd.zst" \
  -append "$kernel_args" -m 8192M

# qemu-system-aarch64 \
#   -M virt -m 8192M -cpu cortex-a53 \
#   -kernel "$script_dir/../result/bzImage" \
#   -initrd "$script_dir/../result/initrd.zst" \
#   -append "console=ttyAMA0,38400n8 rdinit=/bin/sh" \
#   -nographic
