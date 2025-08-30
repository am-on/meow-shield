{ config, lib, pkgs, ... }:

let
  cfg = config.networking.wifi-credentials;
  
  # Read WiFi credentials from JSON file
  wifiCredentials = if cfg.credentialsFile != null then
    builtins.fromJSON (builtins.readFile cfg.credentialsFile)
  else
    {};

  # Generate iwd network configuration files
  mkIwdNetworkFile = ssid: creds: {
    name = "iwd/${ssid}.psk";
    value = {
      text = ''
        [Security]
        Passphrase=${creds.psk}
        
        [Settings]
        AutoConnect=${if creds.autoConnect or true then "true" else "false"}
        ${lib.optionalString (creds.priority or null != null) "Priority=${toString creds.priority}"}
        
        ${lib.optionalString (creds.hiddenSSID or false) "[Network]\nHidden=true"}
      '';
    };
  };

in {
  options.networking.wifi-credentials = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable automatic WiFi connection with credentials from JSON file";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/nixos/wifi-credentials.json";
      description = ''
        Path to JSON file containing WiFi credentials.
        The JSON should have the following structure:
        {
          "network-name": {
            "psk": "pre-shared-key-or-password",
            "passphrase": "optional-passphrase",
            "autoConnect": true,
            "priority": 10,
            "hiddenSSID": false
          }
        }
      '';
    };

    networks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          psk = lib.mkOption {
            type = lib.types.str;
            description = "Pre-shared key (password) for the network";
          };
          passphrase = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional passphrase";
          };
          autoConnect = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to automatically connect to this network";
          };
          priority = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Connection priority (higher numbers = higher priority)";
          };
          hiddenSSID = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this is a hidden network";
          };
        };
      });
      default = {};
      description = "WiFi network configurations (alternative to credentialsFile)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Merge credentials from file and direct configuration
    environment.etc = lib.mapAttrs' mkIwdNetworkFile 
      (wifiCredentials // cfg.networks);

    # Copy credentials to /var/lib/iwd where iwd expects them
    systemd.services.iwd-credentials = {
      description = "Copy WiFi credentials to iwd";
      wantedBy = [ "iwd.service" ];
      before = [ "iwd.service" ];
      after = [ "local-fs.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        mkdir -p /var/lib/iwd
        ${lib.concatMapStrings (ssid: ''
          cp /etc/iwd/${lib.escapeShellArg ssid}.psk /var/lib/iwd/${lib.escapeShellArg ssid}.psk
          chmod 600 /var/lib/iwd/${lib.escapeShellArg ssid}.psk
        '') (lib.attrNames (wifiCredentials // cfg.networks))}
      '';
    };

    # Ensure iwd is enabled and properly configured
    networking.wireless.iwd = {
      enable = true;
      settings = {
        Network = {
          EnableIPv6 = true;
          RoutePriorityOffset = 300;
        };
        Settings = {
          AutoConnect = true;
        };
        General = {
          EnableNetworkConfiguration = true;
        };
      };
    };

    # Ensure networkd is used for network management
    networking.useNetworkd = true;
    
    # Configure systemd-networkd for wireless interfaces
    systemd.network.networks."99-wireless-client-dhcp" = {
      matchConfig.Name = "wlan*";
      networkConfig = {
        DHCP = lib.mkDefault "yes";
        MulticastDNS = lib.mkDefault "yes";
        IPv6AcceptRA = lib.mkDefault true;
      };
      dhcpV4Config = {
        RouteMetric = lib.mkDefault 600;
      };
      dhcpV6Config = {
        RouteMetric = lib.mkDefault 600;
      };
    };
  };
}