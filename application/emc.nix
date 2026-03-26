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

  systemd.services."tcp-echo@" = {
    description = "TCP Echo Service Instance";
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -u STDIN STDOUT";
      StandardInput = "socket";
      StandardOutput = "socket";
      StandardError = "journal";
      # Security hardening
      DynamicUser = true;
    };
  };

  systemd.sockets.tcp-echo = {
    description = "Socket for TCP Echo Service";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "17777" ];
    socketConfig = {
      Accept = "yes";
    };
  };


    systemd.services."usb-echo@" = {
      description = "USB Serial Echo Service on %I";
      stopIfChanged = false;
      serviceConfig = {
        ExecStart =
          let
            # The same echo script logic as before
            echoScript = pkgs.writeShellScript "usb-echo-handler" ''
              # %I will be the device path (e.g., /dev/ttyUSB0)
              # We use 'raw' mode to ensure characters aren't interpreted by the tty driver
              exec ${pkgs.socat}/bin/socat -u FILE:"$1",raw STDOUT | ${pkgs.socat}/bin/socat -u STDIN FILE:"$1",raw
            '';
          in
          "${echoScript} /dev/%i";
        StandardError = "journal";
        Restart = "no"; # Let udev handle the "restart" on replug
      };
    };

    # 2. Use udev to trigger the service
    # This rule matches any USB serial device (ttyUSB or ttyACM)
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="tty", ENV{ID_BUS}=="usb", TAG+="systemd", ENV{SYSTEMD_WANTS}+="usb-echo@%k.service"
    '';
}
