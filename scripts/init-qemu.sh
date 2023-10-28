#!/usr/bin/env bash
# Script to boot up a host using QEMU
# Usage: sh ./scripts/init-qemu.sh <hostname>
# Dependencies: nix, qemu

set -o pipefail
# Specifications
result="./result"
mem="8192M"

# Check if argument was given
if [ $# -ne 1 ]; then
    echo "error: no hostname provided."
    exit 1
else
  hostname="$1"
fi

# Default flags for nix commands
nix_flags=(
  --accept-flake-config
  --extra-experimental-features 'nix-command flakes'
  --no-warn-dirty
  --show-trace
)

# Build the host
nix build .#"$hostname" "${nix_flags[@]}" || exit 1

# Get config.system.build set
build_set=$(nix eval --json .#nixosConfigurations."$hostname".config.system.build) || exit 1

# Launch QEMU based on the format
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
    echo "error: $hostname does not have a supported format."
    exit 1
    ;;
esac
