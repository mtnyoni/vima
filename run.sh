#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$project_dir/native/build.sh" >/dev/null

odin run "$project_dir" -- "$@"
