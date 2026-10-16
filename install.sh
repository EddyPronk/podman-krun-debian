#!/bin/sh
# SPDX-License-Identifier: MIT
set -e

cd "$(dirname "$0")"

if [ ! -f usr-local.tar ]; then
    echo "usr-local.tar not found; run ./build.sh first" >&2
    exit 1
fi

# The tarball's paths are usr/local/..., so it unpacks relative to /.
sudo tar -C / -xf usr-local.tar
sudo /sbin/ldconfig

./test.sh
