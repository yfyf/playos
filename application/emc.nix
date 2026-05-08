{ config, pkgs, lib, ... }:

{
  networking.firewall.enable = lib.mkForce false;
  playos.networking.watchdog.enable = lib.mkForce false;
  playos.selfUpdate.enable = lib.mkForce false;

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
