#!/bin/bash
set -euo pipefail

clone=false
if [[ "${1:-}" == "-c" ]]; then
    clone=true
fi

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"

setup_paths

# clean out/ directory before build
rm -rf "${_src_dir}/out" || true

fetch_sources "$clone"
apply_patches
apply_domsub
apply_branding
generate_patch_manifest
write_gn_args
fix_tool_downloading
provide_dawn_go
setup_toolchain
gn_gen
gn_check_aerium
maybe_build
