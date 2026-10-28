{ pkgs, self }:
pkgs.testers.runNixOSTest {
  name = "observability-stack";
  nodes.monitor =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.default ];
      virtualisation.memorySize = 2048;
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
      services.prometheus.exporters.node.enable = true;
      services.observability-stack = {
        enable = true;
        nodeTargets = [ "localhost:9100" ];
        grafana.adminPasswordFile = "${pkgs.writeText "grafana-pass" "test-only"}";
      };
    };
  testScript = ''
    monitor.wait_for_unit("prometheus.service")
    monitor.wait_for_open_port(9090)
    with subtest("all rule groups are loaded"):
        monitor.wait_until_succeeds(
            "test $(curl -sf localhost:9090/api/v1/rules | jq '.data.groups | length') -eq 3"
        )
    with subtest("node target is scraped"):
        monitor.wait_until_succeeds(
            "curl -sfG localhost:9090/api/v1/query --data-urlencode 'query=up{job=\"node\"}' | jq -e '.data.result[0].value[1] == \"1\"'"
        )
    with subtest("alertmanager, blackbox and loki are ready"):
        monitor.wait_until_succeeds("curl -sf localhost:9093/-/ready")
        monitor.wait_until_succeeds("curl -sf localhost:9115/metrics > /dev/null")
        monitor.wait_until_succeeds("curl -sf localhost:3100/ready")
    with subtest("grafana provisions the fleet dashboard"):
        monitor.wait_for_unit("grafana.service")
        monitor.wait_until_succeeds(
            "curl -sf -u admin:test-only 'localhost:3000/api/search?query=Fleet' | jq -e '.[] | select(.uid == \"fleet-overview\")'"
        )
  '';
}
