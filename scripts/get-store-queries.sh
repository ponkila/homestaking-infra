#!/usr/bin/env bash
# script to get and update nix-store queries
# usage: sh ./scripts/get-store-queries.sh
# deps: nix git

set -o pipefail
trap cleanup EXIT
trap cleanup SIGINT

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
host_path="$script_dir/../nixosConfigurations"

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
    git stash pop
  fi
  exit 0
}

# Fetch hostnames from $host_path
hostnames=($(find "$host_path" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

# Stash any uncommitted changes (including untracked files)
if [[ -n $(git diff --quiet --exit-code) ]]; then
  echo "Stashing uncommitted changes..."
  git stash push --include-untracked
  stash_created=true
fi

# Loop trough hostnames
for hostname in "${hostnames[@]}"; do
  # Remove old query if exists
  file_path="$host_path/$hostname/nix-store-query.txt"
  if [ -f "$file_path" ]; then
    rm "$file_path"
  fi

  # Get sorted build tree
  build_path=$(nix path-info --derivation .#"${hostname}" "${nix_flags[@]}" | tail -n 1)
  nix-store --query --requisites "$build_path" \
    | sort -t'-' -k2 > "$file_path"
done
