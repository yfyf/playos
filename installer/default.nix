# Build NixOS system
{ config, lib, pkgs
, version, safeProductName, fullProductName, greeting, install-playos
}:
let
  configuration = (import ./configuration.nix) {
    inherit install-playos version safeProductName fullProductName greeting;
  };

in
(pkgs.nixos {
  inherit configuration;
  system = "x86_64-linux";
}).config.system.build.isoImage

