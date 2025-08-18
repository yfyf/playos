{ applicationOverlays ? [] }:

let

  nixpkgs = builtins.fetchTarball {
    # staging-next-24.11 2025-01-06
    url = "https://github.com/NixOS/nixpkgs/archive/fe7eff0b925b09b9e03031b0321486a4e923a649.tar.gz";
    sha256 = "1vrjmfs4acj4s7iry9jfygbk1q6smjbj552kx05bnr371wym0ypb";
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
          qtvirtualkeyboard = qtsuper.qtvirtualkeyboard.overrideAttrs (previous: {
                patches = [
                    ./qtvirtualkeyboard/0001-handle-mismatch-between-latest-received-focusObject.patch
                ];

                # Note: according to Qt you should use `qt-configure-module`
                # from qtbase (https://wiki.qt.io/Qt_Build_System_Glossary#Per-repository_Build)
                # for configuration, but the `configure` script crashes due to
                # unknwon type `enableLang` specified in `vkb-enable` (if used) and
                # install fails due to incompatibilities with the nix setup.
                #
                # So instead we set the cmake flag directly and keep the bloated
                # version of qtvirtualkeyboard (handwriting support, spell
                # checker, all languages included, etc).
                cmakeFlags = [
                    "-DFEATURE_vkb_arrow_keynavigation=ON"
                ] ++ (super.lib.lists.optionals (previous ? cmakeFlags) previous.cmakeFlags);
          });
      });

    };
in

import nixpkgs {
  overlays = [ overlay ] ++ applicationOverlays;
}
