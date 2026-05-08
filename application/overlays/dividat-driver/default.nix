{ stdenv, fetchFromGitHub, pkgs, buildGoModule }:

let

  version = "2.8.1-emc";

in buildGoModule rec {

  pname = "dividat-driver";
  inherit version;

  src = fetchFromGitHub {
    owner = "yfyf";
    repo = "driver";
    rev = "emc-tweaks";
    sha256 = "sha256-ChH4UlJp+eAKVf40t0OPngNYWLrzx8ZviRVvuX2h5NM=";
  };

  vendorHash = "sha256-GwV+DmGCYe/PvnimpVbUWziD4SCoZDm0U9aVfmrLqsI=";

  nativeBuildInputs = with pkgs; [ pkg-config pcsclite ];
  buildInputs = with pkgs; [ pcsclite ];

  ldflags = [
    "-X github.com/dividat/driver/src/dividat-driver/server.version=${version}"
  ];

}
