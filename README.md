# Vima

Vima is a graphical application launcher built with Odin, SDL3, and SDL3_ttf.
On supported Wayland compositors it uses the layer-shell protocol, so the
launcher is an overlay instead of a normal application window. It therefore
does not appear in the taskbar or Alt-Tab list. X11 remains available as a
utility-window fallback.

## Fedora requirements

Install the native build and RPM packaging dependencies:

```bash
sudo dnf install \
  binutils \
  gcc \
  SDL3-devel \
  SDL3_image-devel \
  SDL3_ttf-devel \
  desktop-file-utils \
  google-noto-sans-fonts \
  pkgconf-pkg-config \
  rpm-build \
  wayland-devel \
  wayland-protocols-devel
```

Install Odin separately and ensure that `odin` is available on `PATH`:

```bash
odin version
```

## Run from source

Run the project during development:

```bash
./run.sh
```

The wrapper generates and compiles the Wayland protocol shim before invoking
`odin run`. Arguments supplied to the wrapper are passed to Vima.

After `./run.sh` or `./build.sh` has generated `build/native/libvima-wayland.a`,
the regular command also works:

```bash
odin run .
```

On a clean checkout, run `./run.sh` first because Odin cannot compile the C shim
as part of a `foreign import`.

Type-check without launching the window:

```bash
odin check .
```

Vima automatically prefers native Wayland when the compositor advertises
`wlr-layer-shell`. To test a backend explicitly:

```bash
SDL_VIDEO_DRIVER=wayland ./run.sh
SDL_VIDEO_DRIVER=x11 ./run.sh
```

The Wayland surface covers the selected output transparently, while the visible
launcher remains centered. This lets a click outside the launcher close it
without creating a taskbar window. Compositors without layer-shell support fall
back to X11 when XWayland is available.

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
