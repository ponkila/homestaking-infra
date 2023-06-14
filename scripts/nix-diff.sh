#!/bin/bash
# script for getting diffs between current and main branch nix builds
# diffs for a specific hostname: sh ./scripts/nix-diff.sh <hostname>
# diffs for all hostnames: sh ./scripts/nix-diff.sh

set -o pipefail
trap cleanup EXIT
trap cleanup SIGINT

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
host_path="$SCRIPT_DIR/../hosts"
current_branch=$(git rev-parse --abbrev-ref HEAD)
logs_path="/tmp"

# Exclude hosts from $host_path
exclude_hosts=(
  "ponkila-persistent-epsilon"
)

# Default flags for nix-command
nix_flags=(
  --accept-flake-config
  --extra-experimental-features 'nix-command flakes'
)

# Cleanup which will be executed at exit
cleanup() {
  rm -rf "$temp_dir"
}

buidl() {
  local hostname=$1
  local log_prefix=$2

  # Build, output nix log and exit if build fails
  nix build .#"${hostname}" "${nix_flags[@]}" \
    --dry-run --fallback --show-trace -v \
    --log-format raw > "$logs_path/$log_prefix.out.log" 2> "$logs_path/$log_prefix.err.log" \
    || exit 1

  # Get sorted build tree
  build_path=$(nix path-info --derivation .#"${hostname}" "${nix_flags[@]}" | tail -n 1)
  nix-store --query --graph "$build_path" \
    | awk -F'-' '{ print $2, $0 }' | sort -k1 \
    | cut -d' ' -f2- > "$logs_path/${log_prefix}.tree.log"
}

# Check if hostname argument is provided
if [ -z "$hostname" ]; then
  # Fetch hostnames from $host_path
  hostnames=($(find "$host_path" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))
else
  # Use the provided hostname
  hostnames=("$hostname")
fi

# Clone main to temp dir
temp_dir=$(mktemp -d -p "$SCRIPT_DIR")
remote_url=$(git remote show origin | awk '/Push  URL/ {print $3}')
git clone "$remote_url" --branch main --single-branch "$temp_dir"
printf '%.s-' {1..69} && echo

for hostname in "${hostnames[@]}"; do
  # Skip if hostname is in the exclude list
  if [[ " ${exclude_hosts[*]} " =~ $hostname ]]; then
    echo "Skipping '$hostname'."
    printf '%.s-' {1..69} && echo
    continue
  fi

  # Create logs directory
  mkdir -p "$logs_path" 

  # Build from current branch
  echo "Building '$hostname' from '$current_branch'.."
  buidl "$hostname" "$hostname"

  # Build from main branch
  cd "$temp_dir" || exit 1
  echo "Building '$hostname' from 'main'.."
  buidl "$hostname" "$hostname-main"

  # Remove previous diff
  rm -f "$host_path/$hostname/diff.log"
  
  # Result
  diff_out=$(diff "$logs_path/$hostname.tree.log" "$logs_path/$hostname-main.tree.log")

  if [ -n "$diff_out" ]; then
    echo "$diff_out" > "$host_path/$hostname/diff.log"
    echo "Differences found for '$hostname': '$host_path/$hostname/diff.log'"
  else
    echo "No differences found for '$hostname'."
  fi
  printf '%.s-' {1..69} && echo
done
