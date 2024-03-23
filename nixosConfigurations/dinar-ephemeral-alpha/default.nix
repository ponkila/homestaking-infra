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

    # Wireguard options
    vpn.wireguard = {
      enable = true;
      configFile = "/mnt/eth/wg0.conf";
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

  services.promtail = {
    enable = true;
    configuration = {
      server = {
        http_listen_port = 9080;
        grpc_listen_port = 0;
      };
      positions = {
        filename = "/tmp/positions.yaml";
      };
      clients = [{
        url = "url: http://192.168.250.200:3100/loki/api/v1/push";
      }];
      scrape_configs = [{
        job_name = "journal";
        journal = {
          max_age = "12h";
          labels = {
            job = "systemd-journal";
            host = "pihole";
          };
        };
        relabel_configs = [{
          source_labels = [ "__journal__systemd_unit" ];
          target_label = "unit";
          source_labels = [ "__journal__hostname" ];
          target_label = "hostname"; 
          source_labels = [ "__journal_priority_keyword" ];
          target_label = "level";
        }];
      }];
    };
    # extraFlags
  };

  services.netdata.enable = true;

  services.getty.autologinUser = "core";

  system.stateVersion = "23.05";
}
