{config, pkgs, lib, ... }:
let
  cfg = config.playos.remoteMaintenance;
in
{
  options = {
    playos.remoteMaintenance = with lib; {
      enable = mkEnableOption "Remote maintenance";

      jumpHostAddr = mkOption {
        default = null;
        example = "tunnel.domain.com";
        type = types.str;
        description = "FRP server address";
      };

      jumpHostPort = mkOption {
        default = null;
        example = 443;
        type = types.ints.positive;
        description = "FRP server port";
      };

      authorizedKeys = mkOption {
        default = [];
        example = [];
        type = types.listOf types.str;
        description = "Public SSH keys authorized to log in";
      };

      requireOptIn = mkOption {
        default = true;
        example = false;
        description = "With required opt-in the service needs to be started on the machine before remote access is possible";
        type = lib.types.bool;
      };

    };
  };

  config = lib.mkIf cfg.enable {
    # Configure FRP to connect to reverse tunnel SSH to jump host
    services.frp = {
      enable = true;
      role = "client";

      settings = {
        serverAddr = cfg.jumpHostAddr;
        serverPort = cfg.jumpHostPort;
        user = "playos-{{ .Envs.MACHINE_ID }}";
        transport.protocol = "websocket";

        proxies = [{
          name = "ssh";
          type = "tcp";
          localIP = "127.0.0.1";
          localPort = 22;
          remotePort = 0;
        }];
      };
    };

    systemd.services.frp.wantedBy = lib.mkIf cfg.requireOptIn (lib.mkForce []);
    systemd.services.frp.serviceConfig.Environment = ''"MACHINE_ID=%m"'';

    # Allow remote access via OpenSSH
    services.openssh = {
      enable = true;

      # Restrict authentication to authorized keys
      settings.PasswordAuthentication = false;
      settings.KbdInteractiveAuthentication = false;

      # Do not add general firewall exception
      openFirewall = false;

      # Restrict forwarding
      extraConfig = ''
        AllowTcpForwarding local
        X11Forwarding no
        AllowAgentForwarding no
        AllowStreamLocalForwarding no
      '';

    };
    # Only with the specified authorized keys
    users.users.root.openssh.authorizedKeys.keys = cfg.authorizedKeys;
    
  };
}
