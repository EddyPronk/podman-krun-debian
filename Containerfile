# SPDX-License-Identifier: MIT
#
# Builds libkrunfw, libkrun 1.x and crun (+LIBKRUN) into /usr/local, then
# exports only /usr/local. Run it with ./build.sh, install with ./install.sh.

FROM docker.io/library/debian:trixie-slim AS build

ARG LIBKRUNFW_VERSION=v5.6.2
ARG LIBKRUN_VERSION=v1.19.6
ARG CRUN_VERSION=1.30.1

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates git curl xz-utils pkgconf python3 \
        python3-pyelftools flex bison bc libelf-dev \
        libclang-dev \
        autoconf automake libtool go-md2man \
        libsystemd-dev libprotobuf-c-dev libcap-dev libseccomp-dev libjson-c-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain stable
ENV PATH=/root/.cargo/bin:$PATH

WORKDIR /src

# The kernel build is by far the slowest step; keep it in its own layer.
RUN git clone --depth 1 --branch "$LIBKRUNFW_VERSION" https://github.com/libkrun/libkrunfw.git \
    && make -C libkrunfw -j"$(nproc)" \
    && make -C libkrunfw install \
    && rm -rf libkrunfw

# The 1.x Makefile defaults to lib64, which Debian's dynamic loader doesn't search.
RUN git clone --depth 1 --branch "$LIBKRUN_VERSION" https://github.com/libkrun/libkrun.git \
    && make -C libkrun \
    && make -C libkrun LIBDIR_Linux="lib/$(gcc -print-multiarch)" install \
    && rm -rf libkrun

RUN git clone --depth 1 --branch "$CRUN_VERSION" \
        --recurse-submodules --shallow-submodules https://github.com/containers/crun.git \
    && cd crun \
    && ./autogen.sh \
    && ./configure --with-libkrun \
    && make -j"$(nproc)" \
    && make install \
    && /usr/local/bin/crun --version | grep -q +LIBKRUN \
    && cd .. && rm -rf crun

FROM scratch
COPY --from=build /usr/local /usr/local
