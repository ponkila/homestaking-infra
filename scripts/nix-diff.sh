#!/bin/bash
# script for getting diffs between current and main branch nix builds
# deps: git nix
# usage: sh ./scripts/nix-diff.sh <hostname>

set -o pipefail
trap cleanup EXIT
trap cleanup SIGINT

log_path="/tmp"
hostname=$1
nix_flags=(
  --accept-flake-config
  --extra-experimental-features 'nix-command flakes'
)
current_branch=$(git rev-parse --abbrev-ref HEAD)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cleanup() {
  rm -rf "$temp_dir"
}

buidl() {
  local hostname=$1
  local log_prefix=$2

  # Build, output nix log and exit if build fails
  echo "Building '$hostname' from '$current_branch'.."
  nix build .#"${hostname}" "${nix_flags[@]}" \
    --fallback --show-trace -v --log-format raw > >(tee "$log_path/$log_prefix.out.log") 2> >(tee "$log_path/$log_prefix.err.log" >&2) \
    || exit 1

  # Get sorted build tree
  build_path=$(nix path-info --derivation .#"${hostname}" "${nix_flags[@]}" | tail -n 1)
  nix-store --query --graph "$build_path" \
    | awk -F'-' '{ print $2, $0 }' | sort -k1 \
    | cut -d' ' -f2- > "$log_path/${log_prefix}.tree.log"
}

# Check if hostname is provided
if [ -z "$hostname" ]; then
  echo "Error: Please provide the hostname hostname as an argument."
  echo "Usage: $0 <hostname>"
  exit 1
fi

# Create log directory
mkdir -p "$log_path" 

# Build from current branch
buidl "$hostname" "$hostname"

# Clone main to temp dir
temp_dir=$(mktemp -d -p "$DIR")
remote_url=$(git remote show origin | awk '/Push  URL/ {print $3}')
git clone "$remote_url" --branch main --single-branch "$temp_dir"

# Build from main branch
cd "$temp_dir" || exit 1
buidl "$hostname" "$hostname-main"

# Result
printf '%.s-' {1..69} && echo
diff_out=$(diff "$log_path/$hostname.tree.log" "$log_path/$hostname-main.tree.log")

if [ -n "$diff_out" ]; then
  echo "$diff_out" > "$log_path/$hostname.diff.log"
  echo "Differences found: '$log_path/$hostname.diff.log'"
else
  echo "No differences found."
fi
