# Building NixOS (no cross-compile)
Tested on Ubuntu 22.04.2 LTS aarch64, 5.15.0-69-generic

- With Nix package manager
    ```console
    # Let root run the nix installer (optional)
    $ mkdir -p /etc/nix
    $ echo "build-users-group =" > /etc/nix/nix.conf

    # Install Nix in single-user mode
    $ curl -L https://nixos.org/nix/install | sh
    $ . $HOME/.nix-profile/etc/profile.d/nix.sh

    # Install nix-command
    $ nix-env -iA nixpkgs.nix

    # Build
    $ nix build .#<hostname> --extra-experimental-features "nix-command flakes"
    ```

- Within [Docker](https://docs.docker.com/desktop/install/linux-install/) / [Podman](https://podman.io/getting-started/installation)

    ```
    # Dockerfile
    FROM docker.io/nixos/nix

    RUN nix-channel --add https://nixos.org/channels/nixpkgs-unstable
    RUN nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
    RUN nix-channel --update
    RUN nix-env -iA nixpkgs.rsync nixpkgs.nix

    CMD nix build .#<hostname> \
        --extra-experimental-features "nix-command flakes" \
        && rsync -L -r result out && unlink result
    ```

    ```console
    # Build
    $ podman build . --tag nix-builder
    $ podman run -v "$PWD:$PWD":z -w "$PWD" nix-builder
    ```
    ---
    ### Debug notes
    
    This error occurs when `programs.fish.enable` is set to `true`, maybe something to do with [this](https://github.com/NixOS/nixpkgs/blob/f5364316e314436f6b9c8fd50592b18920ab18f9/nixos/modules/programs/fish.nix#L153)
    ```
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
    ```