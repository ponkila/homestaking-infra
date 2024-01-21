#!/usr/bin/env bash
# Script to boot up a host using QEMU

set -o pipefail
# Specifications
result="./result"
mem=$(free -m | awk '/^Mem:/ {print $2 "M"}')
cpucount=$(grep -c '^processor' /proc/cpuinfo)

# Check arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$#" -lt 1 ]; then
    echo "Usage: init-qemu <hostname> [additional qemu args]"
    exit 1
fi

hostname="$1"
shift # Remove the hostname from args

# Default flags for nix commands
nix_flags=(
  --accept-flake-config
  --extra-experimental-features 'nix-command flakes'
  --impure
  --no-warn-dirty
  --show-trace
)

# Build the host
nix build .#"$hostname" "${nix_flags[@]}" || exit 1

# List of supported formats
supported_formats=("kexecTree" "isoImage")

# Iterate over supported formats and launch QEMU if matched
for format in "${supported_formats[@]}"; do
  if [[ "$(nix eval .#nixosConfigurations."$hostname".config.system.build."$format" --apply builtins.isAttrs "${nix_flags[@]}")" == true ]]; then
    case $format in
      kexecTree)
        # Get kernel args from kexec-boot script
        kernel_args=$(sed -n '/--command-line/p' "$result/kexec-boot" | cut -d\" -f2)

        # Launch QEMU with kexecTree format
        qemu-system-x86_64 \
          -kernel "$result/bzImage" \
          -initrd "$result/initrd.zst" \
          -append "$kernel_args" \
          -m "$mem" \
          -enable-kvm \
          -cpu host -smp cores=$cpucount \
          "$@"
      ;;
      isoImage)
        # Launch QEMU with isoImage format
        qemu-system-x86_64 \
          -cdrom "$result/iso/nixos.iso" \
          -m "$mem" \
          -enable-kvm \
          -cpu host -smp cores=$cpucount \
          "$@"
      ;;
    esac
    exit 0
  fi
done

echo "error: $hostname does not have a supported format"
exit 1
