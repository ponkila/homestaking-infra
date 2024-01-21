#!/usr/bin/env bash
# Script to get and update nix-store queries for host configurations

set -o pipefail
trap cleanup EXIT
trap cleanup SIGINT

config_dir="nixosConfigurations"

# Default flags for nix commands
nix_flags=(
  --accept-flake-config
  --extra-experimental-features 'nix-command flakes'
  --impure
  --no-warn-dirty
)

# Cleanup function to be executed at exit
cleanup() {
  # Restore the stashed changes if they were created
  if [[ $stash_created ]]; then
    echo "Restoring stashed changes..."
    git stash pop
  fi
  exit 0
}

# Fetch hostnames from 'flake.nix'
mapfile -t hostnames < <(nix eval --json .#nixosConfigurations --apply builtins.attrNames | jq -r '.[]')

# Stash any uncommitted changes (including untracked files)
if [[ -n $(git diff --quiet --exit-code) ]]; then
  echo "Stashing uncommitted changes..."
  git stash push --include-untracked
  stash_created=true
fi

# Loop through hostnames
for hostname in "${hostnames[@]}"; do
  # Remove old query if it exists
  file_path="$config_dir/$hostname/nix-store-query.txt"
  [ -f "$file_path" ] && rm "$file_path"

  # Get sorted build tree
  build_path=$(nix path-info --derivation .#"${hostname}" "${nix_flags[@]}" | tail -n 1)
  nix-store --query --requisites "$build_path" \
    | sort -t'-' -k2 > "$file_path"
done
