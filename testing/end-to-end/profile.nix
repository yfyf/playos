{pkgs, ...}: {
    imports = [
      (pkgs.importFromNixos "modules/profiles/qemu-guest.nix")
      (pkgs.importFromNixos "modules/testing/test-instrumentation.nix")
    ];

    config = {
        # don't need opengl for running tests, reduces image size vastly
        hardware.opengl.enable = false;

        # Uncomment this to enable log forwarding to the test driver. Useful
        # when debugging very early/late boot stage issues, e.g. if backdoor is
        # not running yet/anymore and/or persistent journald storage is
        # unmounted.
        #services.journald.extraConfig = ''
        #    TTYPath=/dev/ttyS0
        #'';
    };
}
