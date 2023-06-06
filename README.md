# Homestaking-infra
Ethereum home-staking infrastructure powered by Nix

## About
Transparency is crucial for spreading knowledge among Ethereum infrastructures, benefiting new home-stakers and maintainers to improve their existing setup. With Nix, the entire configuration of the real, working infrastructure can be seen at glance. This is extremely useful for those involved in the maintenance of these machines, as it provides a clear understanding of what's under the hood.

We are currently working on [HomestakerOS](https://github.com/ponkila/HomestakerOS) and [Nixobolus](https://github.com/ponkila/nixobolus), which are designed to provide users with an easy way to configure, build and deploy this kind of infrastructure via WebUI.

## Keypoints
- Multiple NixOS configurations for running Ethereum nodes
- Supports declarative disk partitioning via [disko](https://github.com/nix-community/disko)
- Runs on RAM disk, providing significant performance benefits by reducing I/O operations
- Deployment secrets using [sops-nix](https://github.com/Mic92/sops-nix) for secure handling of sensitive information
- Utilization of [ethereum.nix](https://github.com/nix-community/ethereum.nix) providing an up-to-date package management solution
- [Overlays](https://nixos.wiki/wiki/Overlays) offer a convenient and efficient way to manually update or modify packages, ideal for addressing issues with upstream sources
- Offers `isoImage` or `kexecTree` output formats depending on the host configuration

## Structure
- `flake.nix`: Entrypoint for host configurations.
- `home-manager`: Home-manager configurations.
- `hosts`: NixOS configurations. Accessible via `nix build`.
- `modules`: Shared module configurations.
- `overlay`: Patches and version overrides for some packages.
- `pkgs`: Our custom packages.
- `system`: Shared system configurations and formats.

## Hosts
| Hostname | System | Format | Info
|-|-|-|-|
dinar-ephemeral-alpha | x86-64 | isoImage | Lighthouse + Erigon
dinar-ephemeral-beta | x86-64 | isoImage | Lighthouse + Erigon
hetzner-ephemeral-alpha | x86-64 | kexecTree | Dedicated build server
hetzner-ephemeral-beta | aarch64 |  kexecTree | Cloud build server
ponkila-ephemeral-beta | x86-64 | kexecTree | Lighthouse + Erigon
ponkila-ephemeral-gamma | aarch64 | kexecTree | Raspberry Pi 4 
ponkila-persistent-epsilon | x86-64 | | Darwin

Note: Some of these hosts might be currently being set up and will be added to hosts directory soon.

## Building (no cross-compile)
Tested on Ubuntu 22.04.2 LTS aarch64, 5.15.0-69-generic

- With Nix package manager (recommended)
    ```
    nix build .#<hostname>
    ```
    <details>
    <summary>Install Nix</summary>

      # Let root run the nix installer (optional)
      $ mkdir -p $HOME/.config/nix
      $ echo "build-users-group =" > $HOME/.config/nix/nix.conf

      # Install Nix in single-user mode
      $ curl -L https://nixos.org/nix/install | sh
      $ . $HOME/.nix-profile/etc/profile.d/nix.sh

      # Install nix-command
      $ nix-env -iA nixpkgs.nix

      # Allow experimental features (optional)
      $ echo "experimental-features = nix-command flakes" >> $HOME/.config/nix/nix.conf

      # Accept nix configuration from a flake (optional)
      $ echo "accept-flake-config = true" >> $HOME/.config/nix/nix.conf
    </details>

- Within [Docker](https://docs.docker.com/desktop/install/linux-install/) / [Podman](https://podman.io/docs/tutorials/installation#installing-on-linux)
    ```
    podman build . --tag nix-builder --build-arg hostname=<hostname>
    ```

    ```
    podman run -v "$PWD:$PWD":z -w "$PWD" nix-builder
    ```
    <details>
    <summary>Debug notes</summary>

      This error occurs when `programs.fish.enable` is set to `true`
      ...
      building '/nix/store/dgy59sxqj2wq2418f82n14z9cljzjin4-man-cache.drv'...
      error: builder for '/nix/store/dgy59sxqj2wq2418f82n14z9cljzjin4-man-cache.drv' failed with exit code 2
      error: 1 dependencies of derivation '/nix/store/p6lx3x6fxbl7hhch5nnsrxxlcsnw524d-etc-man_db.conf.drv' failed to build
      error: 1 dependencies of derivation '/nix/store/m341zgn4qz0na8pvf3vkv44im3m9i8q0-etc.drv' failed to build
      building '/nix/store/yp47gm038kyizbzl1m8y52jq6brkw0da-system-path.drv'...
      error: 1 dependencies of derivation '/nix/store/31h7aqrpzn2ykbv57xfbyj51zb6pz4fi-nixos-system-ponkila-ephemeral-beta-23.05.20230417.f00994e.drv' failed to build
      error: 1 dependencies of derivation '/nix/store/as1q3nzf9kpxxcsr08n5y4zdsijj80qw-closure-info.drv' failed to build
      error: 1 dependencies of derivation '/nix/store/qzl3krxf1z8viz9z3bxi6h0afhyk4s4y-kexec-boot.drv' failed to build
      error: 1 dependencies of derivation '/nix/store/0ys7pxf0l529gmjpayb9ny37kc68bawf-kexec-tree.drv' failed to build
    </details>

## Disk formatting

We use declarative disk partitioning by [disko](https://github.com/nix-community/disko). For each host, there should be disko script that contains the desired disk layout. There are a lot of [examples](https://github.com/nix-community/disko/tree/master/example) available on how to configure the layout.

To apply the disk layout to a target machine, you'll need to boot the machine using the built image and obtain the `mounts.nix` file for that specific host. Once you have the file, execute the following command:

```
sudo nix run github:nix-community/disko -- --mode zap_create_mount ./mounts.nix
```

This command will format the disks according to the script. Once formatting is complete, reboot the machine and the disks should be ready to use.

## Formats & Deployment

- kexecTree
  
  Outputs: bzImage, initrd, kexec-boot script, and netboot IPXE-script.
  
  Deploy:
  
  ```
  # Run a bash shell that provides the dependencies
  $ nix develop

  # Run kexec-boot script
  $ ./result/kexec-boot
  ```

  <details>
  <summary>Netbooting Raspberry Pi 4 with UEFI Firmware</summary>

    We'll be gathering the boot media (/tftpboot folder for PXE booting) in the /result directory. Make sure you have the following dependencies installed: docker, unzip.

    Clone the project repository, build the EDK2 Raspberry Pi 4 UEFI firmware, and copy the necessary files to the result directory.
    ```
    git clone https://github.com/valtzu/pipxe.git
    cd pixpe
    sudo docker-compose up

    mkdir -p result
    cp pxe/RPI_EFI.fd result
    cp -r pxe/efi result
    ```

    Download the "standard" [RPi4 UEFI releases from Github](https://github.com/pftf/RPi4/releases) (excluding RPI_EFI.fd) and copy the files to the result directory.
    ```
    wget https://github.com/pftf/RPi4/releases/download/v1.34/RPi4_UEFI_Firmware_v1.34.zip
    unzip RPi4_UEFI_Firmware_v1.34.zip -d result -x RPI_EFI.fd
    ```

    Obtain all firmware overlays from the [Raspberry Pi Github repository](https://github.com/raspberrypi/firmware/tree/master/boot/overlays) and add them to the overlays folder in the result directory. When prompted to override files, keep the `miniuart-bt.dtbo` and `upstream-pi4.dtbo` from the UEFI project.
    ```
    cp -n overlays/* result/tftpboot/overlays/
    ```

    Replace the autoexec.ipxe file in the projects folder with your own custom ipxe script.
    ```
    cat > result/efi/boot/autoexec.ipxe << EOF
    #!ipxe
    dhcp
    chain --autofree http://192.168.1.128:8080/netboot.ipxe || shell
    EOF
    ```

    Use rpi-imager to flash "Raspberry Pi OS Lite (32-bit)" to an SD card, boot from it, update the system, and change the boot order using `raspi-config` (Advanced Settings > Boot Order > Network Boot). Finally, remove the SD card and reboot.
    ```
    sudo apt-get update && sudo apt-get full-upgrade
    raspi-config
    ```

  </details>

  <details>
  <summary>Bootstrap from hetzner rescue</summary>

    The installer needs sudo
    ```
    apt install -y sudo
    ```

    Let root run the nix installer
    ```
    mkdir -p /etc/nix
    echo "build-users-group =" > /etc/nix/nix.conf
    ```

    Install Nix in single-user mode
    ```
    curl -L https://nixos.org/nix/install | sh
    . $HOME/.nix-profile/etc/profile.d/nix.sh
    ```

    Install nix-command
    ```
    nix-env -iA nixpkgs.nix
    ```

    Build
    ```
    git clone https://github.com/ponkila/homestaking-infra.git
    nix build --extra-experimental-features "nix-command flakes" .#<hostname>
    ```

    Kexec
    ```
    apt-get install kexec-tools
    ./result/kexec-tree
    ```

   </details>

- isoImage
  
  Outputs: ISO image which is loaded into RAM in stage-1
  
  Deploy: Bootable USB drive via [balenaEtcher](https://etcher.balena.io/) or [Ventoy](https://www.ventoy.net/en/index.html)
