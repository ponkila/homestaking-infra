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
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
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

  # Tommi's toybox
  services.qemuGuest.enable = true;
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

  services.getty.autologinUser = "core";

  system.stateVersion = "23.05";
}
