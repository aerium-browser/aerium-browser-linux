#!/bin/bash
set -euxo pipefail

. "/repo/scripts/shared.sh"

setup_paths

if [ "$_prepare_only" = true ]; then
    fetch_sources false
    apply_patches
    apply_domsub
    apply_branding
    write_gn_args
    fix_tool_downloading
    setup_toolchain
    gn_gen
else
    _task_timeout=18000
    cd "$_src_dir"

    set +e
    # Target list must stay identical to shared.sh's maybe_build(): xdg_mime
    # and xdg_settings are standalone targets, not deps of "chrome", and
    # package.sh's fixed file list expects both. CI used to omit them, so
    # every CI-produced AppImage was missing xdg-mime/xdg-settings (the
    # default-browser and mime-handler integration) while local builds
    # shipped them.
    timeout -k 5m -s INT "${_task_timeout}"s \
        ninja -C out/Default chrome chromedriver xdg_mime xdg_settings
    rc=$?
    set -e

    if [ "${_gha_final}" != "true" ] && [ "$rc" -eq 124 ]; then
        echo "Task timed out after ${_task_timeout}s; continuing in next run."
        echo "status=running" >> "$GITHUB_OUTPUT"
        exit 0
    elif [ "$rc" -eq 0 ]; then
        # A zero exit with missing outputs means ninja considered the graph
        # satisfied without producing what packaging needs - treat that as a
        # failure rather than falling through to `exit 0` with no status set,
        # which silently skipped the remaining parts and then failed in
        # packaging instead.
        for _artifact in chrome chromedriver; do
            if [ ! -x "${_out_dir}/${_artifact}" ]; then
                echo "ninja succeeded but ${_out_dir}/${_artifact} is missing" >&2
                exit 1
            fi
        done
        # xdg-mime/xdg-settings are copied-in shell scripts; only check that
        # they exist, not that the copy preserved the exec bit.
        for _artifact in xdg-mime xdg-settings; do
            if [ ! -e "${_out_dir}/${_artifact}" ]; then
                echo "ninja succeeded but ${_out_dir}/${_artifact} is missing" >&2
                exit 1
            fi
        done
        echo "status=completed" >> "$GITHUB_OUTPUT"
    fi

    exit "$rc"
fi
