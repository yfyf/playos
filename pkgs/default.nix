{ version, updateUrl, kioskUrl, activeVirtualTerminals ? [] }:

let

  nixpkgs = builtins.fetchTarball {
    # nixos-22.11 2023-01-11
    url = "https://github.com/nixos/nixpkgs/archive/54644f409ab471e87014bb305eac8c50190bcf48.tar.gz";
    sha256 = "1pqgwbprmm84nsylp8jjhrwchzn3cv9iiaz1r89mazfil9qcadz0";
  };

  overlay =
    self: super: {

      importFromNixos = path: import (nixpkgs + "/nixos/" + path);

      rauc = (import ./rauc) super;

      dividat-driver = (import ./dividat-driver) {
        inherit (super) stdenv fetchFromGitHub buildGoModule;
        pkgs = self;
      };

      playos-kiosk-browser = import ../kiosk {
        pkgs = self;
        system_name = "PlayOS";
        system_version = version;
      };

      breeze-contrast-cursor-theme = super.callPackage ./breeze-contrast-cursor-theme {};

      ocamlPackages = super.ocamlPackages.overrideScope' (self: super: {
        semver = self.callPackage ./ocaml-modules/semver {};
        obus = self.callPackage ./ocaml-modules/obus {};
      });

      # Controller
      playos-controller = import ../controller {
        pkgs = self;
        version = version;
        updateUrl = updateUrl;
        kioskUrl = kioskUrl;
      };

    };

in

  import nixpkgs {
    overlays = [
      overlay
      (import ./xorg { inherit activeVirtualTerminals; })
    ];
  }
