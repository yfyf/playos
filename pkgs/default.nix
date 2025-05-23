{ applicationOverlays ? [] }:

let

  nixpkgs = builtins.fetchTarball {
    # release-24.11 2025-02-10
    url = "https://github.com/NixOS/nixpkgs/archive/edd84e9bffdf1c0ceba05c0d868356f28a1eb7de.tar.gz";
    sha256 = "1gb61gahkq74hqiw8kbr9j0qwf2wlwnsvhb7z68zhm8wa27grqr0";
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

      wpa_supplicant = super.wpa_supplicant.overrideAttrs (old: {
        version = "2.10";
        src = super.fetchurl {
          url = "https://w1.fi/releases/wpa_supplicant-2.10.tar.gz";
          sha256 = "sha256-IN965RVLODA1X4q0JpEjqHr/3qWf50/pKSqR0Nfhey8=";
        };
	    patches = [];
      });

    };

in

import nixpkgs {
  overlays = [ overlay ] ++ applicationOverlays;
}
