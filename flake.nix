{
  description = "Prometheus, Alertmanager, Grafana, Loki and blackbox_exporter with tested alert rules, for Docker Compose or NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      nixosModules.default = ./nix/module.nix;

      checks = forAllSystems (pkgs: {
        config =
          pkgs.runCommand "observability-config"
            {
              nativeBuildInputs = [
                pkgs.prometheus.cli
                pkgs.prometheus-alertmanager
                pkgs.jq
              ];
            }
            ''
              cd ${self}
              promtool check rules prometheus/rules/*.yml
              promtool test rules prometheus/tests/*.test.yml
              amtool check-config alertmanager/alertmanager.yml
              jq -e '.panels | length > 0' grafana/dashboards/*.json > /dev/null
              # prometheus.yml references container paths; check it against a copy.
              mkdir -p $TMPDIR/etc && cp -r prometheus $TMPDIR/etc/prometheus
              sed "s#/etc/prometheus#$TMPDIR/etc/prometheus#g" prometheus/prometheus.yml > $TMPDIR/p.yml
              promtool check config --syntax-only $TMPDIR/p.yml
              touch $out
            '';
        module = import ./nix/test.nix { inherit pkgs self; };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.prometheus.cli
            pkgs.prometheus-alertmanager
            pkgs.jq
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
