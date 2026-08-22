#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$project_dir/build/packages"

if (( $# != 1 )); then
	echo "usage: $0 VERSION-RELEASE" >&2
	echo "example: $0 0.1.0-4" >&2
	exit 2
fi

package_version="$1"

if [[ ! "$package_version" =~ ^([0-9]+([.][0-9]+)*)-([0-9]+)$ ]]; then
	echo "error: version must use version-release format, for example 0.1.0-3" >&2
	exit 2
fi
version="${BASH_REMATCH[1]}"
release="${BASH_REMATCH[3]}"

for command_name in rpmbuild desktop-file-validate; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "error: $command_name is required" >&2
		echo "install packaging tools with: sudo dnf install rpm-build desktop-file-utils" >&2
		exit 1
	fi
done

"$project_dir/build.sh" --release

mkdir -p "$project_dir/build" "$package_dir"
rpm_topdir="$(mktemp -d "$project_dir/build/rpmbuild.XXXXXX")"
trap 'rm -rf -- "$rpm_topdir"' EXIT

mkdir -p \
	"$rpm_topdir/BUILD" \
	"$rpm_topdir/BUILDROOT" \
	"$rpm_topdir/RPMS" \
	"$rpm_topdir/SOURCES" \
	"$rpm_topdir/SPECS" \
	"$rpm_topdir/SRPMS"

install -m0755 "$project_dir/build/fedora/vima" "$rpm_topdir/SOURCES/vima"
install -m0644 "$project_dir/packaging/vima.desktop" "$rpm_topdir/SOURCES/vima.desktop"
install -m0644 "$project_dir/packaging/vima.spec" "$rpm_topdir/SPECS/vima.spec"

rpmbuild \
	--define "_topdir $rpm_topdir" \
	--define "vima_version $version" \
	--define "vima_release $release" \
	-bb "$rpm_topdir/SPECS/vima.spec"

mapfile -t built_packages < <(find "$rpm_topdir/RPMS" -type f -name 'vima-*.rpm' -print)
if (( ${#built_packages[@]} == 0 )); then
	echo "error: rpmbuild completed without producing an RPM" >&2
	exit 1
fi

for package in "${built_packages[@]}"; do
	output="$package_dir/$(basename -- "$package")"
	install -m0644 "$package" "$output"
	echo "built $output"
done
