#!/bin/bash
# script for getting derivation trees
# usage: sh ./scripts/get-graphs.sh

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
host_path="$SCRIPT_DIR/../hosts"
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Exclude hosts from $host_path
exclude_hosts=(
  "ponkila-persistent-epsilon"
)

# Default flags for nix-command
nix_flags=(
  --no-warn-dirty
  --accept-flake-config
  --extra-experimental-features 'nix-command flakes'
)

buidl() {
  local hostname=$1
  local logs_path="/tmp"

  # Build, output nix log and exit if build fails
  nix build .#"${hostname}" "${nix_flags[@]}" \
    --dry-run --fallback --show-trace -v \
    --log-format raw > "$logs_path/$hostname.out.log" 2> "$logs_path/$hostname.err.log" \
    || exit 1

  # Get sorted build tree
  build_path=$(nix path-info --derivation .#"${hostname}" "${nix_flags[@]}" | tail -n 1)
  nix-store --query --graph "$build_path" \
    | awk -F'-' '{ print $2, $0 }' | sort -k1 \
    | cut -d' ' -f2- > "$host_path/$hostname/digraph.log"
}

# Fetch hostnames from $host_path
hostnames=($(find "$host_path" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

# Build from current branch
for hostname in "${hostnames[@]}"; do
  # Skip if hostname is in the exclude list
  if [[ " ${exclude_hosts[*]} " =~ $hostname ]]; then
    echo "Skipping '$hostname'."
    printf '%.s-' {1..69} && echo
    continue
  fi

  echo "Getting graph for '$hostname'.."
  buidl "$hostname"
done
