{
  version = "v1";
  subnets = [
    {
      name = "simple";
      endpoints = [
        { }
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
          port = 51820;
          ip = "hetzner-ephemeral-alpha.ponkila.com";
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
          port = 51821;
          ip = "nyt2.ponkila.com";
        }
      ];
    }
    {
      name = "kaakkuri";
      subnets = {
        simple = {
          listenPort = 51821;
        };
      };
      endpoints = [
        {
          # no match field means match all peers
          port = 51821;
          ip = "eth.coditon.com";
        }
      ];
    }
  ];
  connections = [
    {
      a = [{ type = "subnet"; rule = "is"; value = "simple"; }];
      b = [{ type = "subnet"; rule = "is"; value = "simple"; }];
      subnets = [ "simple" ];
    }
  ];
}
