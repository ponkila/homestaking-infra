{
  pkgs,
  config,
  inputs,
  lib,
  ...
}: let
  # General
  infra.ip = "192.168.100.31";
in {
  homestakeros = {
    # Localization options
    localization = {
      hostname = "dinar-ephemeral-alpha";
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
      privateKeyFile = "/mnt/eth/ssh/id_ed25519";
    };

    # Wireguard options
    vpn.wireguard = {
      enable = true;
      configFile = "/mnt/eth/wg0.conf";
    };

    # Erigon options
    execution.erigon = {
      enable = true;
      endpoint = "http://${infra.ip}:8551";
      dataDir = "/mnt/eth/erigon";
      jwtSecretFile = "/mnt/eth/jwt.hex";
    };

    # Lighthouse options
    consensus.lighthouse = {
      enable = true;
      endpoint = "http://${infra.ip}:5052";
      execEndpoint = "http://${infra.ip}:8551";
      dataDir = "/mnt/eth/lighthouse";
      slasher = {
        enable = false;
        historyLength = 256;
        maxDatabaseSize = 16;
      };
      jwtSecretFile = "/mnt/eth/jwt.hex";
    };

    # Addons
    addons.mev-boost = {
      enable = true;
      endpoint = "http://${infra.ip}:18550";
    };
    addons.ssv-node = {
      dataDir = "/mnt/eth/ssv";
      privateKeyFile = "/mnt/eth/ssv/ssv_operator_key";
    };

    # Mounts
    mounts.eth = {
      enable = true;
      description = "storage";

      what = "/dev/sda1";
      where = "/mnt/eth";
      type = "ext4";

      wantedBy = ["multi-user.target"];
    };
  };

  services.bitcoind."mainnet" = {
    enable = true;
    prune = "disable";
    dataDir = "/mnt/eth/bitcoin/bitcoind";
    extraCmdlineOptions = [
      "-server=1"
      "-txindex=0"
      "-rpccookiefile=/mnt/eth/bitcoin/bitcoind/.cookie"
    ];
  };

  systemd.services.electrs = {
    enable = true;

    description = "electrum rpc";
    requires = ["wg-quick-wg0.service" "bitcoind-mainnet.service"];
    after = ["wg-quick-wg0.service" "bitcoind-mainnet.service"];

    script = ''      ${pkgs.electrs}/bin/electrs \
            --db-dir /mnt/eth/bitcoin/electrs/db \
            --cookie-file /mnt/eth/bitcoin/bitcoind/.cookie \
            --network bitcoin \
            --electrum-rpc-addr 192.168.100.31:50001
    '';

    wantedBy = ["multi-user.target"];
  };
  networking.firewall.allowedTCPPorts = [50001];
  networking.firewall.allowedUDPPorts = [50001];

  # Tommi's toybox
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
  environment.systemPackages = with pkgs; [
    parted
  ];

  security.audit = {
    enable = true;
    rules = ["-a exit,always -F arch=b64 -S execve"];
  };
  security.auditd.enable = true;

  services.SystemdJournal2Gelf = {
    enable = true;
    graylogServer = "192.168.250.15:12201";
    extraOptions = "--follow";
  };

  services.netdata.enable = true;

  services.getty.autologinUser = "core";

  system.stateVersion = "23.05";
}
