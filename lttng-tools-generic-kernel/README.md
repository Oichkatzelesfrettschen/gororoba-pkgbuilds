# lttng-tools-generic-kernel

## Rationale

The AUR `lttng-tools` package depends on `linux>=2.6.27`, which pulls the stock
Arch `linux` package on CachyOS, EndeavourOS, Manjaro-style, and other
Arch-derived hosts whose installed kernel package has a different name.  LTTng
tools only need userspace dependencies to build and run; kernel tracing support
is provided by matching LTTng modules for the running kernel.

## Package Shape

This package builds LTTng-tools 2.15.0 against the installed userspace stack and
does not depend on a distro-specific kernel package.  Kernel tracing remains an
optional runtime capability through `lttng-modules`.

## Build And Smoke Test

```sh
cd lttng-tools-generic-kernel
makepkg -s
sudo pacman -U ./lttng-tools-generic-kernel-2.15.0-1-x86_64.pkg.tar.zst
lttng version
```

Tests are disabled at package build time because LTTng 2.15 requires
Babeltrace2 2.1 for its test suite.  The installed CLI and daemons are still
built, packaged, and smoke-tested with `lttng version` plus a create, channel,
start, stop, and destroy cycle for a temporary user-space tracing session.
