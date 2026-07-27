#!/bin/bash
set -euo pipefail

_current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
_root_dir="$(cd "${_current_dir}/.." && pwd)"
_git_submodule="ungoogled-chromium"

_image="ungoogled-chromium-trixie-slim:packager"

# Build context is the repo root, not the caller's cwd: package.Dockerfile is
# addressed by absolute path, so a bare "." silently used whatever directory
# the script happened to be invoked from.
docker buildx build --load -t "${_image}" -f "${_root_dir}/docker/package.Dockerfile" "${_root_dir}/docker"

[ -n "$(ls -A "${_root_dir}/${_git_submodule}" 2>/dev/null || true)" ] || git -C "${_root_dir}" submodule update --init --recursive

_user_uidgid="$(id -u):$(id -g)"

cd "${_root_dir}" && docker run --rm -i \
    -u "${_user_uidgid}" \
    -e APPIMAGE_EXTRACT_AND_RUN=1 \
    -v "${_root_dir}:/repo" \
    "${_image}" bash "/repo/scripts/package.sh"
