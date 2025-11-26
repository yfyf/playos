{ applicationOverlays ? [] }:

let

  nixpkgs = builtins.fetchTarball {
    # release-24.11 2025-02-10
    url = "https://github.com/NixOS/nixpkgs/archive/5ab036a8d97cb9476fbe81b09076e6e91d15e1b6.tar.gz";
    sha256 = "0fyhfcii8flpjq644k679nb92vvdv5jwmndimyd9a999p6hzxmwh";
  };

  overlay =
    self: super: {

      importFromNixos = path: import (nixpkgs + "/nixos/" + path);

      rauc = (import ./rauc) super;

      ocamlPackages = super.ocamlPackages.overrideScope (self: super: {
        semver = self.callPackage ./ocaml-modules/semver {};
        obus = self.callPackage ./ocaml-modules/obus {};
        opium = self.callPackage ./ocaml-modules/opium {};
        opium_kernel = self.callPackage ./ocaml-modules/opium_kernel {};
        ppx_protocol_conv = self.callPackage ./ocaml-modules/ppx_protocol_conv {};
        ppx_protocol_conv_jsonm = self.callPackage
            ./ocaml-modules/ppx_protocol_conv_jsonm {};
      });

      connman = (import ./connman) super;

      python3Packages = super.python3Packages.overrideScope (self: super: {
        playos-proxy-utils = self.callPackage ../proxy-utils {};
      });

      qt6 = super.qt6.overrideScope (qtself: qtsuper: {
        qtvirtualkeyboard = (import ./qtvirtualkeyboard) { pkgs = super; qt6 = qtsuper; };
      });

      focus-shift = self.callPackage ./focus-shift.nix {};
    };
in

import nixpkgs {
  overlays = [ overlay ] ++ applicationOverlays;
}
