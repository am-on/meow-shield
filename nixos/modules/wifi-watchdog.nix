{ config, lib, pkgs, ... }:

let
  cfg = config.services.wifi-watchdog;
  
  watchdogScript = pkgs.writeShellScript "wifi-watchdog" ''
    # Check if wlan0 has an IP address
    if ! ${pkgs.iproute2}/bin/ip addr show wlan0 | grep -q "inet "; then
      echo "WiFi not connected, attempting to reconnect..."
      
      # Restart iwd to trigger reconnection
      ${pkgs.systemd}/bin/systemctl restart iwd
      
      # Wait a bit for connection to establish
      sleep 5
      
      # Check again
      if ${pkgs.iproute2}/bin/ip addr show wlan0 | grep -q "inet "; then
        echo "WiFi reconnected successfully"
      else
        echo "WiFi reconnection failed, will retry in 10 seconds"
      fi
    else
      echo "WiFi is connected"
    fi
  '';
in
{
  options.services.wifi-watchdog = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable WiFi connection watchdog";
    };
    
    interval = lib.mkOption {
      type = lib.types.str;
      default = "10s";
      description = "Check interval (systemd time format)";
    };
  };
  
  config = lib.mkIf cfg.enable {
    systemd.services.wifi-watchdog = {
      description = "WiFi Connection Watchdog";
      after = [ "network.target" "iwd.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = watchdogScript;
      };
    };
    
    systemd.timers.wifi-watchdog = {
      description = "WiFi Connection Watchdog Timer";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnBootSec = "30s";  # Start 30s after boot
        OnUnitActiveSec = cfg.interval;  # Run every interval
        Unit = "wifi-watchdog.service";
      };
    };
  };
}