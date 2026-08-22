# Vima

Vima is a graphical application launcher built with Odin, SDL3, and SDL3_ttf.
On Linux it prefers SDL's X11 backend so the launcher can be excluded from the
taskbar, then falls back to Wayland when X11 is unavailable.

## Fedora requirements

Install the native build and RPM packaging dependencies:

```bash
sudo dnf install \
  SDL3-devel \
  SDL3_ttf-devel \
  desktop-file-utils \
  google-noto-sans-fonts \
  pkgconf-pkg-config \
  rpm-build
```

Install Odin separately and ensure that `odin` is available on `PATH`:

```bash
odin version
```

## Run from source

Run the project directly during development:

```bash
odin run .
```

Type-check without launching the window:

```bash
odin check .
```

## Build

Create an optimized release binary:

```bash
./build.sh --release
```

The release binary is written to:

```text
build/fedora/vima
```

For a debug build, run:

```bash
./build.sh --debug
```

`--release` is used when no build mode is provided.

## Build an RPM

The RPM script requires a version in `VERSION-RELEASE` format:

```bash
./package-rpm.sh 0.1.0-4
```

It first creates a release binary with `build.sh`, validates the desktop file,
and then writes the resulting package under `build/packages/`. On Fedora 44 and
x86-64, the example above produces a filename similar to:

```text
build/packages/vima-0.1.0-4.fc44.x86_64.rpm
```

## Install or update the RPM

For a first installation:

```bash
sudo dnf install ./build/packages/vima-0.1.0-4*.rpm
```

To update the currently installed package, build a package with a higher
version or release and pass it to `dnf upgrade`:

```bash
./package-rpm.sh 0.1.0-4
sudo dnf upgrade ./build/packages/vima-0.1.0-4*.rpm
```

Check the installed release with `rpm -q vima`. If it reports `0.1.0-3`, then
`0.1.0-4` is a valid next update. For later code-only rebuilds, increment the
release:

```text
0.1.0-4 -> 0.1.0-5
```

When publishing a new application version, reset the release to `1`:

```text
0.1.0-5 -> 0.2.0-1
```

RPM will not treat a rebuild with the same `Version-Release` as an update. If
you intentionally need to install the exact same version again, use:

```bash
sudo dnf reinstall ./build/packages/vima-0.1.0-4*.rpm
```

Verify the installed version:

```bash
rpm -q vima
```

Remove the installed package:

```bash
sudo dnf remove vima
```

The RPM installs the executable at `/usr/bin/vima` and its desktop entry at
`/usr/share/applications/vima.desktop`.
