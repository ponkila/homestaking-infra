# Homestaking-infra
Ethereum home-staking infrastructure powered by Nix

## About
Transparency is crucial for spreading knowledge among Ethereum infrastructures, benefiting new home-stakers and maintainers to improve their existing setup. With Nix, the entire configuration of the real, working infrastructure can be seen at glance. This is extremely useful for those involved in the maintenance of these machines, as it provides a clear understanding of what's under the hood and makes it easy to see the setup as a whole.

We are currently working on [HomeStakerOS](https://github.com/ponkila/HomestakerOS) and [Nixobolus](https://github.com/ponkila/nixobolus), which are designed to provide users with an easy way to configure, build and deploy this kind of infrastructure via WebUI.

## Keypoints
- Multiple NixOS configurations for running Ethereum nodes
- Uses declarative disk partitioning via [disko](https://github.com/nix-community/disko)
- Runs on RAM disk, providing significant performance benefits by reducing I/O operations
- Deployment secrets using [sops-nix](https://github.com/Mic92/sops-nix) for secure handling of sensitive information
- Utilization of [ethereum.nix](https://github.com/nix-community/ethereum.nix) providing an up-to-date package management solution
- [Overlays](https://nixos.wiki/wiki/Overlays) offer a convenient and efficient way to manually update or modify packages, ideal for addressing issues with upstream sources
- Output is generated by [nixos-generators](https://github.com/nix-community/nixos-generators), which has potential to produce various output formats

## Structure
- `flake.nix`: Entrypoint for host configurations
- `shell.nix`: Devshell for boostrapping (`nix develop` or `nix-shell`)
- `home-manager`: Home-manager configuration
- `hosts`: NixOS configurations, accessible via `nix build .#<hostname>`
  - `ponkila-ephemeral-beta`: x86_64-linux, kexecTree, lighthouse + erigon
  - `ponkila-persistent-epsilon`: x86_64-darwin, persistent 
  - `dinar-ephemeral-alpha`: x86_64-linux, copytoram-iso, lighthouse + erigon
- `modules`: Shared module configurations
- `overlay`: Patches and version overrides for some packages. Accessible via `nix build`
- `pkgs`: Our custom packages. Also accessible via `nix build`
- `system`: Shared system configurations and custom formats