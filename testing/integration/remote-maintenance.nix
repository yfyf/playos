let
  pkgs = import ../../pkgs { };
  inherit (pkgs.importFromNixos "tests/ssh-keys.nix" pkgs)
    snakeOilPrivateKey
    snakeOilPublicKey;

    ssh-config = builtins.toFile "ssh.conf" ''
      UserKnownHostsFile=/dev/null
      StrictHostKeyChecking=no
      IdentityFile /root/.ssh/id_snakeoil
    '';
in
pkgs.testers.runNixOSTest {
  name = "remote maintenance";

  nodes = {
    frpServer = { config, modulesPath, ... }: {
      config = {
        networking.firewall.enable = false;
        services.openssh = {
          enable = true;
        };
        users.users.root.openssh.authorizedKeys.keys = [ snakeOilPublicKey ];

        environment.systemPackages = [ pkgs.jq ];

        services.frp = {
          enable = true;
          role = "server";
          settings = {
            bindAddr = "0.0.0.0";
            bindPort = 7000;

            webServer.addr = "127.0.0.1";
            webServer.port = 7500;
          };
        };
      };
    };

    playosOptIn = { config, nodes, pkgs, ... }: {
      imports = [ ../../base/remote-maintenance.nix ];
      config = {
        playos.remoteMaintenance = {
          enable = true;
          authorizedKeys = [ snakeOilPublicKey ];
          jumpHostAddr = nodes.frpServer.networking.primaryIPAddress;
          jumpHostPort = 7000;
        };
      };
    };

    playosAlwaysOn = { config, nodes, pkgs, ... }: {
      imports = [ ../../base/remote-maintenance.nix ];
      config = {
        playos.remoteMaintenance = nodes.playosOptIn.playos.remoteMaintenance // {
          requireOptIn = false;
        };
      };
    };

    developer = { config, nodes, pkgs, ... }: {
      config = {
      };
    };
  };

  testScript = { nodes }: ''
    def is_frp_operational(node):
        node.wait_for_unit('frp.service')

        machine_id = node.succeed("cat /etc/machine-id").strip()

        jq_cmd = f""" jq -e '.proxies[] | select(.name == "playos-{machine_id}.ssh") | .conf.remotePort' """.strip()

        allocated_port = frpServer.wait_until_succeeds(f"curl -sSf 127.0.0.1:7500/api/proxy/tcp | {jq_cmd}", timeout=20).strip()

        hostname = developer.succeed(f"ssh -J frpServer -oPort={allocated_port} 127.0.0.1 hostname").strip()

        assert hostname == node.name, f"Hostname is {hostname}, SSHed to the wrong machine?"

    start_all()

    developer.wait_for_unit("multi-user.target")
    developer.succeed(
      "mkdir -p /root/.ssh",
      "chmod 700 /root/.ssh",
      "cat '${snakeOilPrivateKey}' > /root/.ssh/id_snakeoil",
      "chmod 600 /root/.ssh/id_snakeoil",
      "cat ${ssh-config} > /root/.ssh/config",
    )

    # Default connection setting does not start FRP service on its own
    playosOptIn.wait_for_unit('multi-user.target')
    playosOptIn.fail('systemctl is-active frp.service')
    playosOptIn.systemctl('start frp.service')
    is_frp_operational(playosOptIn)

    # Auto-connected makes ZT operational on its own
    playosAlwaysOn.wait_for_unit('multi-user.target')
    is_frp_operational(playosAlwaysOn)
  '';
}
