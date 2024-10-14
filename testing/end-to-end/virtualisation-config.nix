{ pkgs, lib, config, ... }:
with lib;
let
    overlayPath = "/tmp/playos-test-disk-overlay.qcow2";
in
{
    options = {
        playos.disk = mkOption {
            type = types.path;
            description = "Path to the pre-built PlayOS system image disk";
        };

        # A hack to allow wrapping the VM start script produced by `qemu-vm.nix`
        # It works by defining a mergable option type that allows arbitrary
        # functions to be applied on top of the original derivation.
        system.build.vm = mkOption {
            type = (types.oneOf [
                types.package
                (types.functionTo types.package)
            ]) // {
                merge = (loc: defs:
                    with lists;
                    let
                        deriv = findSingle
                            (x: attrsets.isDerivation x.value)
                            (throw "Exactly one derivation must be specified, zero found")
                            (throw "Exactly one derivation must be specified, multiple found")
                            defs;
                        transformations = filter (x: ! attrsets.isDerivation x.value) defs;
                    in
                        foldl (acc: f: f.value acc) deriv.value transformations
                );
            };
        };
    };

    config = {
        # Kinda abusing the NixOS testing infra here, because
        # there is no other interface for creating test VMs/nodes.
        #
        # Instead of specifying/building a NixOS system, here we
        # pass an already built disk image, so the options below are mainly
        # for _preventing_ qemu-vm.nix from passing any unnecessary flags to
        # QEMU.
        #
        # Due to this, test driver features requiring
        # `virtualisation.sharedDirectories` (e.g. `copy_from_vm`) are not
        # functional.
        virtualisation.mountHostNixStore = false;
        virtualisation.useHostCerts = false;
        virtualisation.directBoot.enable = false;
        virtualisation.useEFIBoot = true;
        virtualisation.useBootLoader = false;
        virtualisation.diskImage = null;

        # good when debugging in interactive mode
        virtualisation.graphics = true;

        # give it a bit more resources
        virtualisation.memorySize = 2048;
        virtualisation.cores = 2;

        virtualisation.qemu.options = [
            "-enable-kvm"
            # created in the wrapper script below
            "-hda ${overlayPath}"
        ];

        # TODO: this breaks tests because the overlay gets recreated when
        # `vm.shutdown() + vm.start()`, which wipes the data
        # while that is fixable, it just adds too many layers of hacking
        # so parking this for now...
        system.build.vm = (prev:
            pkgs.symlinkJoin {
                # the symlinkJoin wrapper is needed because:
                # - the shell script must be at bin/run-{VM_NAME}-vm
                # - the _derivation_ name needs to NOT match `run-.*-vm`
                # see: https://github.com/NixOS/nixpkgs/blob/890217570a9f6b293d896c64ecb24ab3ce8b5a20/nixos/lib/test-driver/test_driver/machine.py#L215-L232
                name = "disk-vm-start-with-overlay";
                paths = [ (pkgs.writeShellScriptBin "run-${config.system.name}-vm"
                    ''
                    test ! -f "${overlayPath}" || rm -f "${overlayPath}"
                    echo "Creating temporary overlay disk"
                    ${pkgs.qemu}/bin/qemu-img create \
                        -b ${config.playos.disk} \
                        -F raw \
                        -f qcow2 "${overlayPath}"
                    echo "Starting the test VM ${config.system.name}"
                    exec ${lib.getExe prev} "$@"
                    ''
                ) ];
            }
        );
    };
}
