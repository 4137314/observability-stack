# NixOS equivalent of compose.yaml, sharing the same rules, Alertmanager config and dashboards.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.observability-stack;
  root = ../.;
  fileTargets = name: hosts: pkgs.writeText "${name}.json" (builtins.toJSON [ { targets = hosts; } ]);
in
{
  options.services.observability-stack = {
    enable = lib.mkEnableOption "Prometheus, Alertmanager, Grafana, Loki and blackbox_exporter";
    nodeTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "web01.example.com:9100" ];
    };
    httpTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "https://www.example.com" ];
    };
    alertmanagerConfigFile = lib.mkOption {
      type = lib.types.path;
      default = root + "/alertmanager/alertmanager.yml";
    };
    grafana = {
      domain = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
      };
      adminPasswordFile = lib.mkOption {
        type = lib.types.str;
        description = "File with the Grafana admin password (outside the Nix store).";
      };
    };
    retention = lib.mkOption {
      type = lib.types.str;
      default = "30d";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      retentionTime = cfg.retention;
      ruleFiles = lib.filesystem.listFilesRecursive (root + "/prometheus/rules");
      alertmanagers = [ { static_configs = [ { targets = [ "localhost:9093" ]; } ]; } ];
      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [ { targets = [ "localhost:9090" ]; } ];
        }
        {
          job_name = "node";
          file_sd_configs = [ { files = [ "${fileTargets "node" cfg.nodeTargets}" ]; } ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              regex = "([^:]+)(:[0-9]+)?";
              target_label = "instance";
              replacement = "$1";
            }
          ];
        }
        {
          job_name = "blackbox_http";
          metrics_path = "/probe";
          params.module = [ "http_2xx" ];
          file_sd_configs = [ { files = [ "${fileTargets "http" cfg.httpTargets}" ]; } ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "localhost:9115";
            }
          ];
        }
      ];
      alertmanager = {
        enable = true;
        configuration = null;
        configText = builtins.readFile cfg.alertmanagerConfigFile;
      };
      exporters.blackbox = {
        enable = true;
        configFile = root + "/blackbox/blackbox.yml";
      };
    };

    # Same settings as loki/config.yml, with NixOS state paths.
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server.http_listen_port = 3100;
        common = {
          path_prefix = config.services.loki.dataDir;
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
          storage.filesystem = {
            chunks_directory = "${config.services.loki.dataDir}/chunks";
            rules_directory = "${config.services.loki.dataDir}/rules";
          };
        };
        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        limits_config.retention_period = cfg.retention;
        compactor = {
          working_directory = "${config.services.loki.dataDir}/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";
        };
      };
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          domain = cfg.grafana.domain;
        };
        security = {
          admin_password = "$__file{${cfg.grafana.adminPasswordFile}}";
          secret_key = "$__file{/var/lib/grafana/secret_key}";
        };
        users.allow_sign_up = false;
        analytics.reporting_enabled = false;
      };
      provision = {
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            uid = "prometheus";
            type = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            uid = "loki";
            type = "loki";
            url = "http://localhost:3100";
          }
          {
            name = "Alertmanager";
            uid = "alertmanager";
            type = "alertmanager";
            url = "http://localhost:9093";
            jsonData.implementation = "prometheus";
          }
        ];
        dashboards.settings.providers = [
          {
            name = "observability-stack";
            folder = "Fleet";
            options.path = root + "/grafana/dashboards";
          }
        ];
      };
    };

    systemd.services.grafana.preStart = lib.mkBefore ''
      [ -s /var/lib/grafana/secret_key ] || ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/grafana/secret_key
    '';
  };
}
