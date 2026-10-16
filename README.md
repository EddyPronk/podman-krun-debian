# Podman microVMs on Debian trixie with krun

Run each Podman container in its own lightweight KVM virtual machine
(microVM) on Debian 13 (trixie), using the stock Debian Podman.

This builds [crun](https://github.com/containers/crun) with
[libkrun](https://github.com/libkrun/libkrun) support, plus
[libkrunfw](https://github.com/libkrun/libkrunfw), the guest kernel.
Debian trixie doesn't package any of these with krun support. The build
runs inside a `debian:trixie-slim` container, and only `/usr/local` is
installed on the host.

```
podman ──► crun (+LIBKRUN, invoked as "krun") ──dlopen──► libkrun.so.1 ──dlopen──► libkrunfw.so.5
                                                          (VMM)                    (guest kernel)
```

## Quick start

```sh
./build.sh      # podman build → usr-local.tar (no root needed)
./install.sh    # sudo: unpack into /usr/local, ldconfig, then ./test.sh
./test.sh       # check the installed stack at any time
```

The first build takes several minutes, most of it the guest kernel.
You need Podman and access to `/dev/kvm`. See **[INSTALL.md](INSTALL.md)**
for details, versions, and building without a container.

## Validate the install

`./test.sh` checks the whole chain: KVM access, the libraries, the `krun`
link, `+LIBKRUN`, and a real container. To do it by hand:

```sh
crun --version        # last line must include +LIBKRUN
uname -r
podman run --rm --runtime krun docker.io/library/alpine uname -r
```

Expected output:

```
6.12.111+deb13-amd64     # host: Debian's kernel (yours may differ)
6.12.109                 # container: the guest kernel from libkrunfw
```

**The container must report `6.12.109`.** That's the Linux kernel built
into libkrunfw 5.6.2. When the two lines differ, the container ran inside a
VM. When the container prints the host kernel, it ran as a normal
container, so `--runtime krun` wasn't used.

If you build a newer libkrunfw, expect its kernel version instead, and run
`EXPECTED_KERNEL=<version> ./test.sh`.

### If it fails

| Error | Cause | Fix |
|---|---|---|
| `krun: failed to open libkrun.so.1 ...` | libkrun 1.x isn't in the loader cache | `sudo /sbin/ldconfig`; see [INSTALL.md](INSTALL.md#libkrun-1x) |
| `crun --version` lacks `+LIBKRUN` | crun was built without `--with-libkrun` | [INSTALL.md](INSTALL.md#crun-with-libkrun-support) |
| KVM errors at start | No access to `/dev/kvm`, or virtualization is off in the BIOS | Check `ls -l /dev/kvm`, then join the `kvm` group |
| Container prints the host kernel | `--runtime krun` wasn't passed and krun isn't the default runtime | Pass `--runtime krun`, or see the next section |

## Using krun with Podman

krun is a symlink to crun, `/usr/local/bin/krun -> crun`. Run under that
name, crun sets up the container as usual, then starts the workload
inside a microVM through libkrun. Podman needs no changes; you only pick
the runtime.

### Per container

```sh
podman run --rm -it --runtime krun docker.io/library/alpine sh
```

Podman finds `krun` on `PATH`. To use the full path instead, pass
`--runtime /usr/local/bin/krun`.

### As the default runtime

Create or edit `~/.config/containers/containers.conf` (for root:
`/etc/containers/containers.conf`):

```toml
[engine]
runtime = "krun"

[engine.runtimes]
krun = ["/usr/local/bin/krun"]
```

Every `podman run` then uses a VM. For a single normal container, pass
`--runtime crun` or `--runtime runc`.

### VM size

By default, the VM gets all CPUs the process may use and 1024 MiB of RAM.
A `--memory` limit is used instead, if one is set. Use annotations to
size it per container:

```sh
podman run --rm --runtime krun \
    --annotation krun.cpus=2 \
    --annotation krun.ram_mib=512 \
    docker.io/library/alpine sh -c 'nproc; grep MemTotal /proc/meminfo'
```

```
2
MemTotal:         528576 kB
```

The limits are 16 vCPUs at most, and values below 128 MiB RAM are ignored.

### Networking

The default mode, TSI, needs no setup. The guest's sockets are proxied
by the host process, so outbound connections and `-p` port publishing
work like a normal container. Listening on UDP sockets isn't supported.
For a real virtio-net interface, use `--annotation krun.use_passt=1`
(requires `passt`) or `krun.tap_name=<tap>`.

See `man krun` for every annotation and the per-image `.krun_vm.json`
configuration file.

## Files

| File | Purpose |
|---|---|
| `Containerfile` | Builds libkrunfw, libkrun 1.x and crun in `debian:trixie-slim`, exports `/usr/local` |
| `build.sh` | Runs the container build, writes `usr-local.tar` |
| `install.sh` | Unpacks `usr-local.tar` into `/usr/local` with sudo, then runs `test.sh` |
| `test.sh` | Checks the installed stack end to end |
| [INSTALL.md](INSTALL.md) | Versions, dependencies, Debian-specific fixes, manual build |

## License

The scripts and documentation in this repository are [MIT](LICENSE)
licensed. The software they build keeps its own licenses: crun is
GPL-2.0-or-later (libcrun LGPL-2.1-or-later), libkrun is Apache-2.0, and
libkrunfw is LGPL-2.1-only with a GPL-2.0-only Linux kernel inside. This
repository contains no binaries. Don't redistribute `usr-local.tar` without
meeting those licenses' terms.
