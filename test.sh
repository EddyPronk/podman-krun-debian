#!/bin/sh
# SPDX-License-Identifier: MIT
set -e

# The guest kernel built into libkrunfw 5.6.2; change it when libkrunfw is upgraded.
EXPECTED_KERNEL=${EXPECTED_KERNEL:-6.12.109}
IMAGE=docker.io/library/alpine

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

ok() {
    echo "ok: $*"
}

[ -r /dev/kvm ] && [ -w /dev/kvm ] || fail "no read/write access to /dev/kvm"
ok "/dev/kvm is accessible"

for lib in libkrun.so.1 libkrunfw.so.5; do
    /sbin/ldconfig -p | grep -q "$lib " || fail "$lib not in the loader cache (run sudo /sbin/ldconfig)"
    ok "$lib found"
done

[ "$(readlink /usr/local/bin/krun)" = crun ] || fail "/usr/local/bin/krun is not a symlink to crun"
ok "krun -> crun"

/usr/local/bin/crun --version | grep -q +LIBKRUN || fail "crun was built without libkrun support"
ok "crun has +LIBKRUN"

host=$(uname -r)
guest=$(podman run --rm --runtime krun "$IMAGE" uname -r) || fail "container failed to start under krun"
[ "$guest" != "$host" ] || fail "container ran on the host kernel ($host), not in a VM"
[ "$guest" = "$EXPECTED_KERNEL" ] || fail "guest kernel is $guest, expected $EXPECTED_KERNEL"
ok "container ran in a VM: guest kernel $guest, host kernel $host"

echo "All tests passed"
