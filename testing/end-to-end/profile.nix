{pkgs, ...}:
let
  qemu-common = pkgs.importFromNixos "lib/qemu-common.nix" {
    inherit pkgs;
    inherit (pkgs) lib;
  };
in
{

    imports = [
      (pkgs.importFromNixos "modules/profiles/qemu-guest.nix")
      (pkgs.importFromNixos "modules/testing/test-instrumentation.nix")
    ];

    config = {
        # don't need opengl for running tests, reduces image size vastly
        hardware.opengl.enable = false;

        # Enable runtime configuration overrides without rebuilding the disk
        fileSystems = {
            "/mnt/extra-test-files" = {
                device = "extra-test-files";
                fsType = "9p";
                options = [ "nofail" "trans=virtio" "version=9p2000.L" "cache=loose" ];
            };
            "/etc/playos-config.toml" = {
                device = "/mnt/extra-test-files/playos-config.toml";
                options = [ "bind" "nofail" ];
            };
        };

        # test-instrumentation.nix sets this in the boot as kernel param,
        # but since we are booting with a custom GRUB config it has no effect,
        # so instead we set this directly in journald
        services.journald.extraConfig = ''
            TTYPath=/dev/${qemu-common.qemuSerialDevice}
        '';
    };
}
