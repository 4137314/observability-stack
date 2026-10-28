# observability-stack

Monitoring and alerting for a server fleet in one directory: **Prometheus, Alertmanager, Grafana, Loki and blackbox_exporter**, with alert rules that are **unit-tested with `promtool`**. Run it with Docker Compose on any Linux host, or as a NixOS module that shares the same rules and dashboards.

## Docker Compose

```bash
git clone https://github.com/4137314/observability-stack && cd observability-stack
cp .env.example .env
mkdir -p secrets && openssl rand -base64 24 > secrets/grafana_admin_password
cp prometheus/targets/node.example.yml prometheus/targets/node.yml   # list your hosts
cp prometheus/targets/http.example.yml prometheus/targets/http.yml   # list your URLs
$EDITOR alertmanager/alertmanager.yml                                 # your receivers
docker compose up -d
```

Ports bind to `127.0.0.1` by default; put your TLS reverse proxy/VPN in front. Images are pinned to exact versions. Target files are re-read automatically, so adding a host needs no restart.

## NixOS

```nix
{
  imports = [ inputs.observability-stack.nixosModules.default ];
  services.observability-stack = {
    enable = true;
    nodeTargets = [ "web01:9100" "db01:9100" ];
    httpTargets = [ "https://www.example.com" ];
    grafana.adminPasswordFile = "/run/secrets/grafana-admin";
  };
}
```

## What you get

| Alert | Fires when |
| --- | --- |
| `HostDown` | node_exporter unreachable for 3 min (inhibits other alerts for that host) |
| `HostFilesystemAlmostFull` / `HostFilesystemFillingUp` | < 10% free, or predicted full within 24 h |
| `HostMemoryPressure`, `HostHighCpuLoad`, `HostClockSkew` | sustained resource or NTP problems |
| `HostSystemdUnitFailed`, `HostRebootRequired` | failed units; pending reboots older than 3 days |
| `EndpointDown`, `EndpointSlow`, `EndpointCertificateExpiringSoon` | blackbox HTTP probes |
| `CertificateExpiringSoon/Expired`, `BackupTooOld`, `BackupDataCheckFailed`, `OpsCheckStale` | metrics from [ops-toolkit](https://github.com/4137314/ops-toolkit) |

Critical alerts go to the `oncall` receiver (repeat 1 h), everything else to `default`. The **Fleet overview** Grafana dashboard covers host status, CPU, memory, disks, network, certificates, backup age and failed units, with an instance filter.

## Feeding it

- [nixos-fleet](https://github.com/4137314/nixos-fleet) `fleet.monitoring` opens exporters only to this server.
- [ansible-baseline](https://github.com/4137314/ansible-baseline) `node_exporter` + `firewall` do the same on Debian/RHEL.
- [ops-toolkit](https://github.com/4137314/ops-toolkit) adds certificate, backup and SSH-key metrics.

## Development

```bash
nix flake check -L   # promtool rule unit tests, amtool, config syntax, NixOS VM test of the whole stack
```

Add an alert by editing `prometheus/rules/*.yml` and adding a case to `prometheus/tests/rules.test.yml`.

## License

MIT. Need on-call-ready monitoring for your infrastructure? Open an issue or contact me via [GitHub](https://github.com/4137314).
