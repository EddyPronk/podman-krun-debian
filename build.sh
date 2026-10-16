#!/bin/sh
# SPDX-License-Identifier: MIT
set -e

cd "$(dirname "$0")"

# The Containerfile goes in on stdin so there's no build context to upload.
# Extra arguments are passed to podman, e.g. --build-arg CRUN_VERSION=1.30.1
podman build -o type=tar,dest=usr-local.tar "$@" - < Containerfile

echo "Built $(pwd)/usr-local.tar; install it with ./install.sh"
