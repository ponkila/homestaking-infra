{ config
, etcd
, jq
, writeShellApplication
, lib
,
}: writeShellApplication {
  name = "wheres-the-postgres";
  runtimeInputs = [ etcd jq ];
  text = ''
    while read -r line; do
      etcdctl put /skydns/nix/ponkila/postgresql/ "$(jq -cn --arg value "$line" '{"host": $value, "ttl":0}')" --endpoints="${lib.concatStringsSep "," config.services.etcd.listenClientUrls}"
    done < <(etcdctl watch --prefix /service/${config.services.patroni.scope}/leader --endpoints="${lib.concatStringsSep "," config.services.etcd.listenClientUrls}" -w json | stdbuf -oL jq -r '.Events[].kv | select(.create_revision) | .value | @base64d')
  '';
  meta.longDescription = ''
    # wheres-the-postgres?

    _wheres-the-postgres_ is an event-based approach to resolving the patroni "leader", i.e., the postgresql cluster primary node, and propagating that change to an *internal* etcd backed CoreDNS instance (hence a time-to-live of 0), in this case, to postgresql.ponkila.nix
    This script relies on the assumption that patroni node names correspond to their intranet addresses, since that is the value echoed by `etcdctl watch`

    Some notes:
    - patroni leader <> etcd leader
    - etcd `watch` catches all HTTP methods regarding to a key, thus `jq` in the process substitution selects creation requests (.create_revision field exists)
    - `stdbuf` flushes pipe buffer --> changes visible for the while loop

    etcd consensus makes this safe to run on all instances, and this *should* be run on all instances for downtime scenarios

    Compared to patroni's provided HAProxy config which polls patroni's HTTP endpoint, this one is event-based.
    Now, HAProxy is redundant, and etcd commits announces fresh leader rather than the formula `etcd commit + HAProxy poll interval`.
    This is not necessarily a replacement to HAProxy: here, application behavior differs by how DNS queries are cached: e.g., `ping` on DNS entry does not change the endpoint if the leader changes.
    Hence, assume change visibility via DNS affects only fresh clients.
    Danger: writes of caching clients will fail because postgresql replicas cannot commit transactions.
  '';
}
