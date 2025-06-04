let
  pkgs = import ../../pkgs { };
  kioskDomain = "kiosk.local";
  kioskUrl = "http://${kioskDomain}/";
  toString = builtins.toString;
  headerFile = "/tmp/http-headers";
in
pkgs.nixosTest {
  name = "connectivity-check";

  nodes = {
    sidekick = { config, lib, ...} : {
      virtualisation.vlans = [ 1 ];

      networking.firewall.enable = false;

      networking.dhcpcd.enable = false;

      networking.primaryIPAddress = "192.168.1.${toString config.virtualisation.test.nodeNumber}";

      systemd.services.http-server = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart =
            let
              respond = pkgs.writeScript "respond.sh" ''
                #!${pkgs.bash}/bin/bash
                echo "HTTP/1.1 200 OK"
                cat "${headerFile}" || true
              '';
            in
            "${pkgs.nmap}/bin/ncat -lk -p 80 -c ${respond}";
          Restart = "always";
        };
      };

      services.dnsmasq.enable = true;
      services.dnsmasq.settings = {
          dhcp-option = [
              "3,${config.networking.primaryIPAddress}" # self as gateway
              "6,${config.networking.primaryIPAddress}" # self as DNS
          ];
          dhcp-range = "192.168.1.30,192.168.1.99,1h";
          address = [
              "/${kioskDomain}/${config.networking.primaryIPAddress}"
              "/${kioskDomain}/${config.networking.primaryIPv6Address}"
          ];
      };

      networking.extraHosts = lib.mkOverride 0 "";
    };

    banana = { config, pkgs, lib, ... }: {
      imports = [
        (import ../../base/volatile-root.nix { # needed for connman dir
            inherit config pkgs lib;
        })
        (import ../../base/networking.nix {
            inherit pkgs lib;
            hostName = "banana";
            config = config // { playos.kioskUrl = kioskUrl; };
        })
        #"${modulesPath}/services/networking/dnsmasq.nix"
      ];

      virtualisation.vlans = [ 1 ];

      # disable QEMU `-net user` interface
      virtualisation.qemu.networkingOptions = lib.mkOverride 0 [ ];
      networking.extraHosts = lib.mkOverride 0 "";

      # TODO: these don't seem to work, there's still a static IP :/
      networking.primaryIPAddress = lib.mkOverride 0 "";
      networking.primaryIPv6Address = lib.mkOverride 0 "";

      # Override is needed to enable in test VM, see connman tests:
      # https://github.com/NixOS/nixpkgs/blob/1772251828be641110eb9a47ef530a1252ba211e/nixos/tests/connman.nix#L47-L52
      services.connman.enable = pkgs.lib.mkOverride 0 true;

      #services.connman.extraFlags = [ "-d" ];

      environment.systemPackages = [
        pkgs.curl
        pkgs.connman
      ];
    };
  };

  extraPythonPackages = ps: [
    ps.colorama
    ps.types-colorama
  ];


  testScript =
    ''
    ${builtins.readFile ../helpers/nixos-test-script-helpers.py}

    def set_header(key, val):
      sidekick.succeed(f'echo "{key}: {val}" > ${headerFile}')

    def set_good_header():
        set_header("X-ConnMan-Status", "online");

    def set_bad_header():
        set_header("foo", "bar")

    start_all()

    sidekick.wait_for_unit('local-fs.target')
    set_good_header()

    sidekick.wait_for_unit('http-server.service')

    banana.wait_for_unit('connman.service')

    # wait for DHCP to complete
    # should be two IPs, one static 192.168.1.1 and one extra
    with TestPrecondition("banana gets and IP from sidekick DHCP"):
        banana.wait_until_succeeds("ip a | grep -v '192.168.1.1' | grep 192.168.1.",
                                 timeout=20)

    with TestPrecondition('curl request to kiosk URL works from banana VM'):
        banana.succeed('curl --fail ${kioskUrl}')

    with TestCase("connman transitions into online state"):
        banana.wait_until_succeeds("connmanctl state | grep 'State = online'",
                                 timeout=10)

    with TestCase("connman transitions into ready state when kiosk is missing X-ConnMan-Status header"):
        set_bad_header()
        banana.wait_until_succeeds("connmanctl state | grep 'State = ready'",
                                 timeout=30)

    with TestCase("connman transitions back into online state when header is restored"):
        set_good_header()
        banana.wait_until_succeeds("connmanctl state | grep 'State = online'",
                                 timeout=30)

    #with TestCase("connman transitions into ready state when kiosk is stopped"):
    #    sidekick.systemctl('stop http-server.service')
    #    banana.wait_until_succeeds("connmanctl state | grep 'State = ready'",
    #                             timeout=30)

    #with TestCase("connman transitions back into online state when kiosk is started"):
    #    sidekick.systemctl('start http-server.service')
    #    banana.wait_until_succeeds("connmanctl state | grep 'State = online'",
    #                             timeout=10)
'';

}

