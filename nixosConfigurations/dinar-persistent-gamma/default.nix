{
  config,
  pkgs,
  ...
}: let
  sshKeysPath = "/etc/ssh/ssh_host_ed25519_key";
in {
  imports = [./hw-config.nix];

  # Bootloader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  # Support for cross compilation
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];

  # Qemu
  services.qemuGuest = {
    enable = true;
    package =
      (pkgs.qemu_kvm.override {
        alsaSupport = false;
        pulseSupport = false;
        pipewireSupport = false;
        jackSupport = false;

        gtkSupport = false;
        sdlSupport = false;
        openGLSupport = false;
        virglSupport = false;
      })
      .ga;
  };

  nixie = {
    enable = true;
    file-server = {
      defaultAddress = "192.168.100.5";

      # Each of these objects represents one iPXE menu
      menus = [
        {
          name = "tupakkatapa";
          flakeUrl = "github:tupakkatapa/nix-config";
          hosts = ["bandit"];
          buildRequests = true;
        }
        # https://github.com/ponkila/homestaking-infra
        {
          name = "ponkila";
          flakeUrl = "github:ponkila/homestaking-infra";
        }
        {
          name = "Afrikantahti";
          flakeUrl = "github:Afrikantahti/homestaking-infra\?ref=Afrikantahti-patch-1";
          hosts = [
            "dinar-ephemeral-alpha"
            "dinar-ephemeral-beta"
          ];
          default = "dinar-ephemeral-alpha";
          buildRequests = true;
          timeout = 1;
        }
      ];
    };

    dhcp = {
      enable = true;
      subnets = [
        {
          name = "upstream";
          serve = true;
          address = "192.168.240.88";
          interfaces = ["ens18"];
          defaultMenu = "tupakkatapa";
          clients = [
            {
              menu = "Afrikantahti";
              mac = "bc:24:11:d0:6b:fd";
              address = "192.168.240.89";
            }
          ];
          poolStart = "192.168.240.100";
          poolEnd = "192.168.240.110";
        }
      ];
    };
  };

  homestakeros = {
    # Localization options
    localization = {
      hostname = "dinar-persistent-gamma";
      timezone = "Europe/Helsinki";
    };

    # SSH options
    ssh = {
      authorizedKeys = [
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCkfHIgiK8S5awFn+oOdduS2mp5UGT4ki/ndoMArBol1dvRSKAdHS4okCX/umiy4BqAsDFkpYWuwe897NdOosba0iVyrFsYRou9FrOnQIMRIgtAvaOXeo2U4432glzH4WsMD+D+F4wHZ7walsrkaIPihpoHtWp8DkTPcFm1D8GP1o5TNpTjSFSuPFSzC2nburVcyfxZJluh/hxnxtYLNrmwOOHLhXcTmy5rQQ5u2HI5y64tS6fnKxxozA2gPaVro5+W5e3WtpSDGdd2NkPDzrMMmwYFEv4Tw9ooUfaJhXhq7AJakK/nTfpLquL9XSia8af+aOzx/p1v25f56dESlhNzcSlREP52hTA9T3foCA2IBkDitBeeGhUeeerQdczoRFxxSjoI244bPwAZ+tKIwO0XFaxLyd3jjzlya0F9w1N7wN0ZO4hY1NVv7oaYTUcU7TnvqGEMGLZpQBnIn7DCrUjKeW4AIUGvxcCP+F16lqFkuLSCgOAHM59NECVwBAOPGDk="
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJdbU8l66hVUAqk900GmEme5uhWcs05JMUQv2eD0j7MI juuso@starlabs"
      ];
      privateKeyFile = sshKeysPath;
    };

    # Wireguard options
    vpn.wireguard = {
      enable = true;
      configFile = config.sops.secrets."wireguard/wg0".path;
    };
  };

  # Secrets
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets."wireguard/wg0" = {};
    secrets."nix-serve/secretKeyFile" = {};
    age.sshKeyPaths = [sshKeysPath];
  };

  # Binary cache
  services.nix-serve = {
    enable = true;
    package = pkgs.nix-serve-ng;
    openFirewall = true;
    port = 5000;
    bindAddress = "192.168.100.5";
    secretKeyFile = config.sops.secrets."nix-serve/secretKeyFile".path;
  };

  system.stateVersion = "23.11";
}
