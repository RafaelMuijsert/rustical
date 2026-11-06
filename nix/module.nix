{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  cfg = config.services.rustical;

  format = pkgs.formats.toml { };
  # `null` is not representable in TOML. Dropping these keys lets the Rust
  # defaults apply, which is what the module's nullable options intend.
  settings = lib.filterAttrsRecursive (_: value: value != null) cfg.settings;
  configFile = format.generate "rustical.toml" settings;
in

{
  # Disable the module shipped with nixpkgs so this fork's module can be used as
  # a drop-in replacement for `services.rustical`.
  disabledModules = [ "services/web-apps/rustical.nix" ];

  options.services.rustical = {
    enable = mkEnableOption "RustiCali CalDAV/CardDAV server";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.rustical.packages.${pkgs.stdenv.hostPlatform.system}.default";
      description = ''
        The RustiCal package to use.

        Defaults to the package exported by this flake (built from the
        RafaelMuijsert/rustical fork).
      '';
    };

    settings = mkOption {
      description = ''
        Your {file}`/etc/rustical/config.toml` as a Nix attribute set.

        Possible options can be found in the [Config struct]. A default
        configuration can be viewed by running `rustical gen-config`.

        [Config struct]: https://lennart-k.github.io/rustical/_crate/rustical/config/struct.Config.html
      '';
      type = types.submodule {
        freeformType = format.type;
        options = {
          data_store.sqlite = {
            db_url = mkOption {
              type = types.str;
              default = "/var/lib/rustical/db.sqlite3";
              description = ''
                Path or URL where the sqlite database is stored.
              '';
            };

            run_repairs = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Whether to run repair tasks on startup.
              '';
            };

            skip_broken = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Whether to skip (and hide) broken calendar and addressbook
                objects instead of failing.
              '';
            };
          };

          frontend = {
            enabled = mkEnableOption "the HTTP frontend" // {
              default = true;
            };

            allow_password_login = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Whether to allow logging into the frontend with a password.
              '';
            };
          };

          http = {
            bind = mkOption {
              type = types.str;
              default = "unix:/run/rustical/sock";
              example = "[::]:4000";
              description = ''
                Address and port or UNIX socket path to bind the HTTP service to.

                :::{.note}
                Rustical expects to be hosted behind a reverse proxy that
                provides HTTPS. Without HTTPS, the web frontend and some clients
                (e.g. Apple Calendar) may not work.
                :::
              '';
            };

            session_cookie_samesite_strict = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether to mark the session cookie as `SameSite=Strict`.
              '';
            };

            payload_limit_mb = mkOption {
              type = types.ints.positive;
              default = 4;
              description = ''
                Maximum accepted request payload size in MiB.
              '';
            };
          };

          caldav.rfc7809 = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Whether to enable RFC 7809 CalDAV support.
            '';
          };

          dav_push = {
            enabled = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Whether to enable [WebDav Push] support.

                This allows the server to notify clients about changed data.

                [WebDav Push]: https://github.com/bitfireAT/webdav-push/
              '';
            };

            allowed_push_servers = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              example = [ "https://push.example.com" ];
              description = ''
                Push servers that clients are allowed to subscribe to. When
                `null`, any push server is accepted.
              '';
            };
          };

          nextcloud_login.enabled = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Whether to emulate the Nextcloud login flow.

              This is supported in [DAVx5] and enables automatic app token generation.

              [DAVx5]: https://www.davx5.com/
            '';
          };
        };
      };
    };

    environmentFiles = mkOption {
      type = with types; listOf path;
      default = [ ];
      example = [ "/run/keys/rustical.env" ];
      description = ''
        Environment files to load into the runtime environment.

        Check the documentation for how to construct [environment variables].

        :::{.tip}
        Environment variables can substitute any config value and are useful for
        hiding secrets.
        :::

        [environment variables]: https://lennart-k.github.io/rustical/installation/configuration/#environment-variables
      '';
    };
  };

  config = mkIf cfg.enable {
    warnings = lib.optionals (cfg.settings.http ? host || cfg.settings.http ? port) [
      ''
        Rustical deprecated options

        The following options are deprecated and will be removed in a future
        release:
        - `services.rustical.settings.http.host`
        - `services.rustical.settings.http.port`

        Migrate to `services.rustical.settings.http.bind` instead.
      ''
    ];

    # Install the config at a path where the CLI will find it.
    environment.etc."rustical/config.toml".source = configFile;

    # Provide the rustical CLI.
    environment.systemPackages = [ cfg.package ];

    systemd.services.rustical = {
      description = "RustiCal CalDav/CardDav server";
      documentation = [ "https://lennart-k.github.io/rustical/" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ configFile ];

      serviceConfig = {
        DynamicUser = true;
        ExecStart = "${lib.getExe cfg.package} --config-file ${configFile} serve";
        EnvironmentFile = cfg.environmentFiles;
        Restart = "on-failure";
        StateDirectory = "rustical";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "rustical";
        RuntimeDirectoryMode = "0750";

        CapabilityBoundingSet = "";
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged @resources"
        ];
        SystemCallErrorNumber = "EPERM";
        UMask = "0007";
      };
    };
  };
}
