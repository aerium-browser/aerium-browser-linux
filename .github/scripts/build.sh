#!/bin/bash
set -euxo pipefail

. "/repo/scripts/shared.sh"

setup_paths

# The pre-flight does everything preparation does and then compiles only the
# sources Aerium owns - see _aerium_preflight_targets in scripts/shared.sh.
# Separate from _prepare_only rather than folded into it because prepare's
# output is the build cache the real build resumes from, and this must not
# produce one: half a compile in the cache would be restored by build_part_01
# as if it were a clean tree.
if [ "${_preflight:-false}" = true ] || [ "${_prepare_only:-false}" = true ]; then
    fetch_sources false
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
    if [ "${_preflight:-false}" = true ]; then
        aerium_preflight
    fi
else
    _task_timeout=18000
    cd "$_src_dir"

    set +e
    # Target list must stay identical to shared.sh's maybe_build(): asking
    # ninja for "xdg_mime"/"xdg_settings" by name fails with "unknown
    # target" - they aren't separately nameable ninja targets, they're data
    # dependencies produced while building "chrome" itself (verified against
    # upstream ungoogled-chromium-portablelinux's own shared.sh, which is
    # exactly `ninja chrome chromedriver` and still successfully packages
    # both files). An earlier revision of this script added them to the
    # command line to fix a real gap - CI-produced AppImages really were
    # missing xdg-mime/xdg-settings - but named them wrong; the existence
    # checks below are the correct way to guard the same regression without
    # asking ninja for a target that doesn't exist.
    timeout -k 5m -s INT "${_task_timeout}"s \
        ninja -C out/Default chrome chromedriver
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
        # xdg-mime/xdg-settings are copied-in shell scripts produced as a
        # side effect of building "chrome" (see the comment above); only
        # check that they exist, not that the copy preserved the exec bit.
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
