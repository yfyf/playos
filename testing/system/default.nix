{pkgs, lib, kioskUrl, playos-controller, application}:

(pkgs.nixos {
  configuration = {...}: {
  imports = [
    # Base layer
    (import ../../base {
      inherit pkgs kioskUrl playos-controller;
      inherit (application) safeProductName fullProductName greeting version;
    })

    # Application-specific
    application.module

    # Testing machinery
    ./testing.nix
  ];
  };
  system = "x86_64-linux";
}).config.system.build.toplevel
