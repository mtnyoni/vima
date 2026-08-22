#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
native_dir="$project_dir/native"
output_dir="$project_dir/build/native"
protocol="$native_dir/wlr-layer-shell-unstable-v1.xml"
protocol_header="$output_dir/wlr-layer-shell-unstable-v1-client-protocol.h"
protocol_source="$output_dir/wlr-layer-shell-unstable-v1-protocol.c"
xdg_protocol="${XDG_SHELL_PROTOCOL:-/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml}"
xdg_source="$output_dir/xdg-shell-protocol.c"

for command_name in cc ar wayland-scanner pkg-config; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "error: $command_name is required for the Wayland launcher backend" >&2
		exit 1
	fi
done

if ! pkg-config --exists wayland-client; then
	echo "error: wayland-client development files are missing" >&2
	echo "install them with: sudo dnf install wayland-devel" >&2
	exit 1
fi

if [[ ! -f "$xdg_protocol" ]]; then
	echo "error: xdg-shell protocol definitions are missing" >&2
	echo "install them with: sudo dnf install wayland-protocols-devel" >&2
	exit 1
fi

mkdir -p "$output_dir"
wayland-scanner client-header "$protocol" "$protocol_header"
wayland-scanner private-code "$protocol" "$protocol_source"
wayland-scanner private-code "$xdg_protocol" "$xdg_source"

read -r -a wayland_cflags <<< "$(pkg-config --cflags wayland-client)"
cc -std=c11 -O2 -fPIC "${wayland_cflags[@]}" -I"$output_dir" \
	-c "$protocol_source" -o "$output_dir/layer-shell-protocol.o"
cc -std=c11 -O2 -fPIC "${wayland_cflags[@]}" -I"$output_dir" \
	-c "$xdg_source" -o "$output_dir/xdg-shell-protocol.o"
cc -std=c11 -O2 -fPIC "${wayland_cflags[@]}" -I"$output_dir" \
	-c "$native_dir/vima_layer_shell.c" -o "$output_dir/vima-layer-shell.o"
ar rcs "$output_dir/libvima-wayland.a" \
	"$output_dir/vima-layer-shell.o" \
	"$output_dir/layer-shell-protocol.o" \
	"$output_dir/xdg-shell-protocol.o"

echo "$output_dir/libvima-wayland.a"
