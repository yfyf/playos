{config, pkgs, lib, ... }:
{
  # Enable non-free firmware
  hardware.enableRedistributableFirmware = true;

  # Set up networking with ConnMan
  # We need to work around various issues in the interplay of
  # connman and wpa_supplicant for this to work.
  networking = {
    hostName = "playos";
    connman = {
      enable = true;
      enableVPN = false;
      networkInterfaceBlacklist = [ "vmnet" "vboxnet" "virbr" "ifb" "ve" "zt" ];
      extraConfig = ''
        [General]
        AllowHostnameUpdates=false
        AllowDomainnameUpdates=false

        # Wifi will generally be used for internet, use as default route
        PreferredTechnologies=wifi,ethernet

        # Allow simultaneous connection to ethernet and wifi
        SingleConnectedTechnology=false

        # Disable calling home
        EnableOnlineCheck=false
      '';
    };
    # Issue 1: Add a dummy network to make sure wpa_supplicant.conf
    # is created (see https://github.com/NixOS/nixpkgs/issues/23196)
    wireless = {
      enable = true;
      networks."12345-i-do-not-exist"= {};
    };
  };
  # Issue 2: Make sure connman starts after wpa_supplicant
  systemd.services."connman".after = [ "wpa_supplicant.service" ];
  # Issue 3: Leave time for rfkill to unblock WLAN and restart connman
  systemd.timers."restart-connman" = {
    timerConfig = {
      OnBootSec = 15;
      RemainAfterElapse = false;
    };
    wantedBy = [ "timers.target" ];
  };
  systemd.services."restart-connman" = {
    description = "Restart connman to enable WLAN";
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = "/run/current-system/sw/bin/systemctl try-restart connman.service";
  };

  # Make connman folder persistent
  volatileRoot.persistentFolders."/var/lib/connman" = {
    mode = "0700";
    user = "root";
    group = "root";
  };
}
