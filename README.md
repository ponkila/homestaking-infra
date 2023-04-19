# Homestaking-infra
Ethereum home-staking infrastructure powered by Nix

## About
Transparency is crucial for spreading knowledge among Ethereum infrastructures, benefiting new home-stakers and maintainers to improve their existing setup. With Nix, the entire configuration of the real, working infrastructure can be seen at glance. This is extremely useful for those involved in the maintenance of these machines, as it provides a clear understanding of what's under the hood and makes it easy to see the setup as a whole.

We are working on [HomeStakerOS WebUI](https://github.com/ponkila/HomestakerOS) and [Nixobolus](https://github.com/ponkila/nixobolus), which are designed to provide users with an easy way to configure and deploy this kind of infrastructure.

## Keypoints
- Multiple NixOS configurations for running Ethereum nodes
- Deployment secrets using [sops-nix](https://github.com/Mic92/sops-nix) for secure handling of sensitive information
- Utilization of [ethereum.nix](https://github.com/nix-community/ethereum.nix) providing an up-to-date package management solution
- The output is generated using [nixos-generators](https://github.com/nix-community/nixos-generators), which has potential to produce various output formats
- Runs on RAM disk, which can provide significant performance benefits by reducing I/O operations
- Uses mount by-label BTRFS mountpoints for blockchain data as well as other relevant files

## Structure
- `shell.nix`: Devshell for boostrapping (`nix develop` or `nix-shell`)
- `flake.nix`: Entrypoint for host configurations.
- `home-manager`: Home-manager configuration.
- `hosts`: NixOS configurations, accessible via `nix build .#<hostname>`
  - `ponkila-ephemeral-beta`
  - `ponkila-persistent-epsilon`
  - `dinar-ephemeral-alpha`
- `modules`: Shared module configurations.
- `overlay`: Patches and version overrides for some packages. Accessible via `nix build`
- `pkgs`: Our custom packages. Also accessible via `nix build`
- `system`: Shared system configurations.