#!/bin/bash
set -euo pipefail
set -x

TIMES=$1

test_script="$(nix-build -A driver testing/integration/controller-wifi.nix)/bin/nixos-test-driver"

for time in `seq 1 $TIMES`; do
    echo "========= Run #$time"
    if $test_script; then
        echo "Run #$time succeeded!"
    else
        echo "Failed on run #$time"
        exit 1
    fi

done

echo "All runs succeeed"
