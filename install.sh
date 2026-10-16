#!/bin/sh
# SPDX-License-Identifier: MIT
set -e

# Usage: ./install.sh [tarball]
# Defaults to the usr-local.tar written by ./build.sh; a downloaded release
# tarball (.tar.gz) works too.
tarball=${1:-$(dirname "$0")/usr-local.tar}

if [ ! -f "$tarball" ]; then
    echo "$tarball not found; run ./build.sh first or pass a release tarball" >&2
    exit 1
fi

# The tarball's paths are usr/local/..., so it unpacks relative to /.
sudo tar -C / -xf "$tarball"
sudo /sbin/ldconfig

"$(dirname "$0")/test.sh"
