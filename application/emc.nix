{ config, pkgs, lib, ... }:

{
  networking.firewall.enable = lib.mkForce false;
  playos.networking.watchdog.enable = lib.mkForce false;
  playos.selfUpdate.enable = lib.mkForce false;

  # wpa_supplicant tweaks
  networking.wireless.extraConfig = lib.mkForce ''
    # During EMC events the AP can vanish from the air for tens of seconds.
    # Keep BSS entries in wpa_supplicant's cache effectively forever so
    # connman doesn't have to rediscover the network before each reconnect
    # attempt.
    bss_expiration_age=86400
    bss_expiration_scan_count=1000000
  '';

  # Periodically force connman to re-scan wifi. By default connman has a
  # BackgroundScan backoff of max 5 minutes, which gets reset on a manual scan
  # request.
  systemd.services.wifi-retry = {
    description = "Force connman to re-scan wifi for EMC reconnect retries";
    after = [ "connman.service" ];
    requisite = [ "connman.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.connman}/bin/connmanctl scan wifi";
    };
  };

  systemd.timers.wifi-retry = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
      Unit = "wifi-retry.service";
    };
  };

  systemd.services.proxy-nocsp = {
    description = "mitmdump background proxy (strips CSP headers)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.mitmproxy}/bin/mitmdump --modify-headers '/~s/Content-Security-Policy/' --set confdir=/var/lib/mitmdump-csp --listen-port 9191";

      # Automatically restart if it crashes
      Restart = "always";
      RestartSec = "5s";
      DynamicUser = true;
      StateDirectory = "mitmdump-csp";
    };
  };
}
