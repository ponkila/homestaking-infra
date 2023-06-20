#!/usr/bin/env bash
# script to update and get nix-store queries
# usage: sh ./scripts/get-store-quaries.sh
# deps: git nix

set -o pipefail
trap cleanup EXIT
trap cleanup SIGINT

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
host_path="$script_dir/../hosts"

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

# Cleanup to be executed at exit
cleanup() {
  # Restore the stashed changes if they were created
  if [[ $stash_created ]]; then
    echo "Restoring stashed changes..."
    git stash pop >/dev/null
  fi
  exit 0
}

# Remove old queries
find "$script_dir/.." -type f -name 'nix-store-query.txt' -exec rm -f {} \;

# Stash any uncommitted changes (including untracked files)
if [[ -n $(git diff --quiet --exit-code) ]]; then
  echo "Stashing uncommitted changes..."
  git stash push --include-untracked >/dev/null
  stash_created=true
fi

# Fetch hostnames from $host_path
hostnames=($(find "$host_path" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

# Build from the current branch
for hostname in "${hostnames[@]}"; do
  # Skip if hostname is in the exclude list
  if [[ " ${exclude_hosts[*]} " =~ $hostname ]]; then
    echo "Skipping '$hostname'"
    continue
  fi

  # Get sorted build tree
  build_path=$(nix path-info --derivation .#"${hostname}" "${nix_flags[@]}" | tail -n 1)
  nix-store --query --requisites "$build_path" | sort -t'-' -k2 > "$host_path/$hostname/nix-store-query.txt"

done
