{ pkgs
, config
, lib
, ...
}:
{
  boot.initrd.availableKernelModules = [
    "dm_mod"
    "btrfs"
  ];
  fileSystems."/etc/ssh" = lib.mkImageMediaOverride {
    fsType = "btrfs";
    device = "/dev/disk/by-label/nvme";
    options = [ "subvolid=256" ];
    neededForBoot = true;
  };

  homestakeros = {
    # Localization options
    localization = {
      hostname = "ponkila-ephemeral-sigma";
      timezone = "Europe/Helsinki";
    };

    # SSH options
    ssh = {
      authorizedKeys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAILn/9IHTGC1sLxnPnLbtJpvF7HgXQ8xNkRwSLq8ay8eJAAAADHNzaDpzdGFybGFicw== ssh:starlabs"
      ];
    };

    vpn.wireguard = {
      enable = true;
      configFile = "/etc/wireguard/dinar.conf";
    };

    mounts = {
      wireguard = {
        enable = true;
        description = "wireguard storage";

        what = "/dev/disk/by-label/nvme";
        where = "/etc/wireguard";
        type = "btrfs";
        options = "subvolid=257";

        before = [ "wg-quick-dinar.service" ];
        wantedBy = [ "multi-user.target" ];
      };
    };
  };

  systemd.network = {
    enable = true;
    networks = {
      "10-wan" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp1s0";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
        dns = [ "127.0.0.1:1053" ];
      };
      "20-wan" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp2s0";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
        dns = [ "127.0.0.1:1053" ];
        address = [ "192.168.17.22/24" ]; # static IP
      };
    };
  };
  networking = {
    firewall.allowedUDPPorts = [ 51822 ];
    nameservers = [ "127.0.0.1:1053" ];
    useDHCP = false;
  };
  services.coredns = {
    enable = true;
    config = ''
      .:1053 {
        forward . 1.1.1.1 {
          health_check 5s
        }
        cache 30
      }
    '';
  };

  environment.systemPackages = with pkgs; [
    lighthouse
  ];

  # Secrets
  age = {
    rekey = {
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINMEbHrkxwZAsdv+V9moza0VTKY97R/qeennww20FUID";
    };
    secrets = { };
  };

  services.netdata = {
    enable = true;
  };

  wirenix = {
    enable = true;
    peerName = "ponkila-ephemeral-sigma"; # defaults to hostname otherwise
    configurer = "networkd"; # defaults to "static", could also be "networkd"
    keyProviders = [ "agenix-rekey" ]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
    secretsDir = ../../nixosModules/wirenix/agenix; # only if you're using agenix-rekey
    aclConfig = import ../../nixosModules/wirenix/acl.nix;
  };

  system.stateVersion = "25.05";
}
