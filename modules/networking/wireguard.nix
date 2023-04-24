{ pkgs, config, inputs, lib, ... }:
{
  systemd.services.wg0 = {
    enable = true;

    description = "wireguard interface for cross-node communication";
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
    };

    preStart = "${pkgs.wireguard-tools}/bin/wg-quick down /run/user/1000/wireguard/wg0.conf || true";
    script = ''${pkgs.wireguard-tools}/bin/wg-quick \
      up /run/user/1000/wireguard/wg0.conf
    '';

    wantedBy = [ "multi-user.target" ];
  };
}
