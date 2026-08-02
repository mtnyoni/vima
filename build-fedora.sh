#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
output_dir="$project_dir/build/fedora"
mode="${1:---release}"

if ! command -v odin >/dev/null 2>&1; then
	echo "error: Odin is not installed or is not on PATH" >&2
	exit 1
fi

if ! command -v pkg-config >/dev/null 2>&1; then
	echo "error: pkg-config is required (sudo dnf install pkgconf-pkg-config)" >&2
	exit 1
fi

if ! pkg-config --exists sdl3 sdl3-ttf; then
	echo "error: SDL3 development packages are missing" >&2
	echo "install them with: sudo dnf install SDL3-devel SDL3_ttf-devel" >&2
	exit 1
fi

if [[ ! -f /usr/share/fonts/google-noto/NotoSans-Regular.ttf ]]; then
	echo "error: Noto Sans is missing" >&2
	echo "install it with: sudo dnf install google-noto-sans-fonts" >&2
	exit 1
fi

mkdir -p "$output_dir"

case "$mode" in
	--debug)
		build_flags=(-debug)
		;;
	--release)
		build_flags=(-o:speed)
		;;
	*)
		echo "usage: $0 [--release|--debug]" >&2
		exit 2
		;;
esac

odin build "$project_dir" \
	"-out:$output_dir/vima" \
	"${build_flags[@]}"

echo "built $output_dir/vima"
