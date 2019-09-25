# overlay for custom packages
system_version: self: super: {

  rauc = (import ./rauc) super;

  dividat-driver = (import ./dividat-driver) {
    inherit (super) stdenv fetchurl;
  };

  playos-kiosk-browser = self.callPackage ../kiosk {
    inherit system_version;
    system_name = "PlayOS";
  };

  # pin pcsclite to 1.8.23 because of break in ABI (https://github.com/LudovicRousseau/PCSC/commit/984f84df10e2d0f432039e3b31f94c74e95092eb)
  pcsclite = super.pcsclite.overrideAttrs (oldAttrs: rec {
    version = "1.8.23";
    src = super.fetchurl {
      url = "https://pcsclite.apdu.fr/files/pcsc-lite-${version}.tar.bz2";
      sha256 = "1jc9ws5ra6v3plwraqixin0w0wfxj64drahrbkyrrwzghqjjc9ss";
    };
  });
}
