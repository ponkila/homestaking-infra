{ nixosConfigurations
, subnetName
, lib
}:

let
  pred = lib.filter (n: nixosConfigurations.${n}.config.mesh.enable) (builtins.attrNames nixosConfigurations);
  peers = lib.map
    (n: {
      name = nixosConfigurations.${n}.config.wirenix.peerName;
      endpoints = [ nixosConfigurations.${n}.config.mesh.endpoint ];
      subnets.${subnetName}.listenPort = nixosConfigurations.${n}.config.mesh.endpoint.port;
    })
    pred;
in
{
  inherit peers;
  version = "v1";
  subnets = [
    {
      name = subnetName;
      endpoints = [{ }];
    }
  ];
  connections = [
    {
      a = [{ type = "subnet"; rule = "is"; value = subnetName; }];
      b = [{ type = "subnet"; rule = "is"; value = subnetName; }];
      subnets = [ subnetName ];
    }
  ];
}
