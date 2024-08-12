{
  version = "v1";
  subnets = [
    {
      name = "simple";
      endpoints = [
        {
          # No match mean match any
          port = 51820;
        }
      ];
    }
  ];
  peers = [
    {
      name = "node1";
      subnets = {
        simple = {
          listenPort = 51820;
          # no ipAddresses field will auto generate an IPv6 address
        };
      };
      endpoints = [
        {
          # no match can be any
          ip = "135.181.90.126";
        }
      ];
    }
    {
      name = "node2";
      subnets = {
        simple = {
          listenPort = 51821;
        };
      };
      endpoints = [
        {
          # no match field means match all peers
          ip = "nyt2.ponkila.com";
        }
      ];
    }
  ];
  connections = [
    {
      a = [{ type = "subnet"; rule = "is"; value = "simple"; }];
      b = [{ type = "subnet"; rule = "is"; value = "simple"; }];
    }
  ];
}
