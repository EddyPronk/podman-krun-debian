# Building and installing

There are two ways to build the stack: in a container with the scripts,
or by hand on the host. Both install into `/usr/local` and produce the same
result.

| Component | Version | Repository | Installs |
|---|---|---|---|
| libkrunfw | `v5.6.2` | https://github.com/libkrun/libkrunfw | `libkrunfw.so.5.6.2`, Linux 6.12.109 guest kernel |
| libkrun | `v1.19.6` | https://github.com/libkrun/libkrun | `libkrun.so.1.19.6`, the VMM |
| crun | `1.30.1` | https://github.com/containers/crun | `crun` with `+LIBKRUN`, and the `krun` link |

Podman itself is the stock Debian package; it doesn't need rebuilding.

## Requirements

- Debian 13 (trixie), x86_64.
- **Podman**: `sudo apt-get install podman`.
- **KVM**: `/dev/kvm` must be accessible to the user running Podman. On a
  desktop login, systemd-logind grants this through an ACL
  (`crw-rw----+`). Otherwise, add the user to the `kvm` group. KVM is
  only needed to *run* containers, not to build.

## Container build (recommended)

```sh
./build.sh
./install.sh
```

`build.sh` runs `podman build` on the `Containerfile` and writes
`usr-local.tar`. `install.sh` unpacks it with `sudo tar -C / -xf
usr-local.tar`, runs `sudo /sbin/ldconfig`, and then `./test.sh`.

- **Versions** are build arguments. Override them through `build.sh`,
  which passes extra arguments to podman:
  ```sh
  ./build.sh --build-arg LIBKRUNFW_VERSION=v5.6.2 \
             --build-arg LIBKRUN_VERSION=v1.19.6 \
             --build-arg CRUN_VERSION=1.30.1
  ```
- **Build context:** the Containerfile is passed on stdin, so no build
  context is uploaded. Each project is cloned fresh inside the container.
- **Normal runtime:** the build uses Podman's normal runtime, not krun.
- **Output:** the final stage is `FROM scratch` holding only `/usr/local`,
  so the tarball (~36 MB) contains just the files in
  [Installed files](#installed-files), plus empty directories from the
  base image. All entries are owned by `root:root`.
- **Checks:** the build fails if `crun --version` doesn't report
  `+LIBKRUN`.
- **Network:** the build downloads from deb.debian.org, sh.rustup.rs,
  GitHub, crates.io, and cdn.kernel.org.
- **Host libraries:** the exported binaries link against the host's
  `libsystemd0`, `libseccomp2`, `libcap2` and `libjson-c5`. A stock trixie
  install with Podman already has these.
- **Cleanup:** the build leaves a ~1.9 GB untagged builder image. Remove
  it with `podman image prune`.

## Manual build

These are the steps the `Containerfile` runs, for building on the host
directly.

### Dependencies

```sh
sudo apt-get install -y \
    build-essential ca-certificates git curl xz-utils pkgconf python3 \
    python3-pyelftools flex bison bc libelf-dev \
    libclang-dev \
    autoconf automake libtool go-md2man \
    libsystemd-dev libprotobuf-c-dev libcap-dev libseccomp-dev libjson-c-dev
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

| Packages | Needed by |
|---|---|
| `python3-pyelftools flex bison bc libelf-dev curl xz-utils` | libkrunfw: kernel tarball download and kernel build |
| `libclang-dev` | libkrun: `bindgen` needs the unversioned `libclang.so` and clang headers. Without it the build fails in `clang-sys` with *couldn't find any valid shared libraries matching: ['libclang.so', ...]* |
| `libc6-dev` (via `build-essential`) | libkrun: links its guest init with `-static` |
| `autoconf automake libtool go-md2man libsystemd-dev libprotobuf-c-dev libcap-dev libseccomp-dev libjson-c-dev` | crun |
| Rust from rustup | libkrun |

Build in this order: crun's `configure` needs the libkrun header
installed.

### libkrunfw

```sh
git clone --branch v5.6.2 https://github.com/libkrun/libkrunfw.git
make -C libkrunfw -j"$(nproc)"    # downloads the kernel tarball, then builds the kernel
sudo make -C libkrunfw install
```

The Makefile detects Debian and installs to `/usr/local/lib/x86_64-linux-gnu`.

### libkrun 1.x

```sh
git clone --branch v1.19.6 https://github.com/libkrun/libkrun.git
make -C libkrun
sudo make -C libkrun LIBDIR_Linux=lib/$(gcc -print-multiarch) install
sudo /sbin/ldconfig
```

- **`LIBDIR_Linux=...` is required on Debian.** The libkrun 1.x Makefile
  defaults to `/usr/local/lib64`, which Debian's dynamic loader doesn't
  search. crun then fails at container start, not at build time, with:
  ```
  Error: krun: failed to open `libkrun.so.1`, `libkrun-sev.so.1`, and `libkrun-awsnitro.so.1` ...
  ```
- **`ldconfig` is in `/sbin`,** which isn't on a normal user's `PATH`.
- **Use a 1.x release, not libkrun's `main` branch.** `main` is libkrun
  2.0, which isn't compatible with the 1.x API and has the soname
  `libkrun.so.2`. crun `dlopen()`s `libkrun.so.1`
  (`src/libcrun/handlers/krun.c`). `configure --with-libkrun` only checks
  that *a* `libkrun.h` exists, so a crun built against the 2.0 header
  still reports `+LIBKRUN`, but every container fails at start.

### crun with libkrun support

```sh
git clone --branch 1.30.1 --recurse-submodules https://github.com/containers/crun.git
cd crun
./autogen.sh
./configure --with-libkrun
make -j"$(nproc)"
sudo make install
crun --version    # feature line must include +LIBKRUN
```

- **The `libocispec/` submodule is required.** Without
  `--recurse-submodules` the directory is empty and the build fails. Fix
  it with `git submodule update --init --recursive`.
- **`make install` creates the `krun` link,**
  `/usr/local/bin/krun -> crun`.
- **`--enable-shared` isn't needed.** It only builds `libcrun.so` for
  programs that embed crun.

Then run `./test.sh`.

## Installed files

| Path | From |
|---|---|
| `/usr/local/lib/x86_64-linux-gnu/libkrunfw.so{,.5,.5.6.2}` | libkrunfw |
| `/usr/local/lib/x86_64-linux-gnu/libkrun.so{,.1,.1.19.6}` | libkrun |
| `/usr/local/lib/x86_64-linux-gnu/pkgconfig/libkrun.pc` | libkrun |
| `/usr/local/include/libkrun.h`, `libkrun_display.h`, `libkrun_input.h` | libkrun |
| `/usr/local/bin/crun`, `/usr/local/bin/krun` | crun |
| `/usr/local/lib/libcrun.a`, `/usr/local/lib/libcrun.la` | crun |
| `/usr/local/share/man/man1/crun.1`, `krun.1` | crun |

Installing overwrites an existing `/usr/local/include/libkrun.h` and
`libkrun.so` link, for example from a libkrun 2.0 install. An existing
`libkrun.so.2` is left alone.

## Upgrading

Pick new versions and pass them as build arguments, or edit the `ARG`
defaults in the `Containerfile`:

- **libkrunfw** sets the guest kernel (`KERNEL_VERSION` in its
  `Makefile`). After upgrading, update `EXPECTED_KERNEL` in `test.sh`.
- **libkrun** must stay on a 1.x release (`v1.*` tags, `stable-1.*`
  branches). Check that its `KRUNFW_NAME` in `src/libkrun/src/lib.rs`
  matches the libkrunfw soname, currently `libkrunfw.so.5`.
- **crun** needs a release whose krun handler still loads `libkrun.so.1`.
