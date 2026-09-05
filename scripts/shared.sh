#!/bin/bash
set -euo pipefail

# shared build functions used by local and CI scripts

# resolve repo root directory regardless of caller location
repo_root() {
    local _base_dir
    _base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    cd "${_base_dir}/.." >/dev/null 2>&1 && pwd
}

setup_arch() {
    _host_arch=$(uname -m)

    if [ "$_host_arch" = "x86_64" ]; then
        _host_arch="x64"
    elif [ "$_host_arch" = "aarch64" ]; then
        _host_arch="arm64"
    fi

    _build_arch="$_host_arch"
    if [ -n "${ARCH:-}" ]; then
        _build_arch="$ARCH"
    fi

    if [ "$_build_arch" = "x86_64" ]; then
        _build_arch=x64
    fi
}

setup_paths() {
    _root="$(repo_root)"
    _main_repo="${_root}/ungoogled-chromium"
    _build_dir="${_root}/build"
    _dl_cache="${_build_dir}/download_cache"
    _src_dir="${_build_dir}/src"
    _out_dir="${_src_dir}/out/Default"
    setup_arch

    # Go (see provide_dawn_go) refuses to run without a writable build cache,
    # and the container runs as the host's uid with no real home directory, so
    # its default ~/.cache path isn't writable. Keep these OUT of ${_build_dir}:
    # export-cache.sh tars that whole directory into the inter-stage artifact.
    export GOCACHE="${TMPDIR:-/tmp}/aerium-gocache"
    export GOPATH="${TMPDIR:-/tmp}/aerium-gopath"

    mkdir -p "${_dl_cache}"
}

# Dawn's Tint build step shells out to a Go program to generate real production
# sources (lang/core/enums.cc, intrinsic/data.cc, ...), from a toolchain it
# expects at third_party/dawn/tools/golang/<host-platform>/bin/go. That comes
# from a cipd entry in dawn's *own* DEPS, so gclient checkouts get it for free
# but our tarball checkout does not, and the build dies with:
#   FileNotFoundError: '.../third_party/dawn/tools/golang/linux-amd64/bin/go'
# Point that path at the distro Go installed in the build image instead.
provide_dawn_go() {
    local _go _plat _dest
    _go="$(command -v go || true)"
    if [ -z "$_go" ]; then
        echo "provide_dawn_go: no 'go' on PATH (is golang-go installed in the build image?)" >&2
        return 1
    fi

    # Host platform, not target: this generator runs on the build machine even
    # when cross-compiling to arm64.
    case "$(uname -m)" in
        x86_64) _plat=linux-amd64 ;;
        aarch64) _plat=linux-arm64 ;;
        *) echo "provide_dawn_go: unhandled host arch $(uname -m)" >&2; return 1 ;;
    esac

    _dest="${_src_dir}/third_party/dawn/tools/golang/${_plat}/bin"
    mkdir -p "${_dest}"
    ln -sf "${_go}" "${_dest}/go"
}

fetch_sources() {
    local use_clone="${1:-false}"
    local stamp="${_src_dir}/.downloaded.stamp"

    if [ -f "${stamp}" ]; then
        echo "Sources already present, skipping download/unpack"
        return 0
    fi

    if ${use_clone}; then
        _host_arch_clone="$_host_arch"
        if [ "$_host_arch_clone" = x64 ]; then
            _host_arch_clone="amd64"
        fi

        "${_main_repo}/utils/clone.py" --sysroot "$_host_arch_clone" -o "${_src_dir}"
    else
        "${_main_repo}/utils/downloads.py" retrieve -i "${_main_repo}/downloads.ini" -c "${_dl_cache}"
        "${_main_repo}/utils/downloads.py" unpack -i "${_main_repo}/downloads.ini" -c "${_dl_cache}" "${_src_dir}"
    fi

    touch "${stamp}"
}

apply_patches() {
    if [ ! -f "${_src_dir}/.patched.stamp" ]; then
        "${_main_repo}/utils/prune_binaries.py" "${_src_dir}" "${_main_repo}/pruning.list"
        "${_main_repo}/utils/patches.py" apply "${_src_dir}" "${_main_repo}/patches" "${_root}/patches"
        touch "${_src_dir}/.patched.stamp"
    fi
}

apply_domsub() {
    if [ ! -f "${_src_dir}/.domsub.stamp" ]; then
        "${_main_repo}/utils/domain_substitution.py" apply -r "${_main_repo}/domain_regex.list" -f "${_main_repo}/domain_substitution.list" "${_src_dir}"
        touch "${_src_dir}/.domsub.stamp"
    fi
}

apply_branding() {
    if [ ! -f "${_src_dir}/.branded.stamp" ]; then
        python3 "${_root}/scripts/apply_branding.py"
        touch "${_src_dir}/.branded.stamp"
    fi
}

# Writes the data behind chrome://aerium. Runs after apply_domsub deliberately:
# domain substitution rewrites hostnames throughout the tree, and generating
# before it would mangle any URL appearing in a patch description into the
# unreachable placeholder domain.
generate_patch_manifest() {
    if [ ! -f "${_src_dir}/.patchmanifest.stamp" ]; then
        python3 "${_root}/scripts/generate_patch_manifest.py" \
            --series "${_main_repo}/patches/series" "${_main_repo}/patches" \
            --series "${_root}/patches/series" "${_root}/patches" \
            --chromium-version "$(cat "${_main_repo}/chromium_version.txt")" \
            -o "${_src_dir}/chrome/browser/ui/webui/aerium_patch_manifest.inc"
        touch "${_src_dir}/.patchmanifest.stamp"
    fi
}

write_gn_args() {
    mkdir -p "${_out_dir}"

    cat "${_main_repo}/flags.gn" "${_root}/flags.linux.gn" | tee "${_out_dir}/args.gn"
    echo "target_cpu = \"$_build_arch\"" | tee -a "${_out_dir}/args.gn"
    echo "v8_target_cpu = \"$_build_arch\"" | tee -a "${_out_dir}/args.gn"
}

# fix downloading of prebuilt tools and sysroot files
# (https://github.com/ungoogled-software/ungoogled-chromium/issues/1846)
fix_tool_downloading() {
    sed -i 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' \
        "${_src_dir}/build/linux/sysroot_scripts/sysroots.json" \
        "${_src_dir}/tools/clang/scripts/update.py" \
        "${_src_dir}/tools/clang/scripts/build.py"

    sed -i 's/chromium.9oo91esource.qjz9zk/chromium.googlesource.com/g' \
        "${_src_dir}/tools/clang/scripts/build.py" \
        "${_src_dir}/tools/rust/build_rust.py" \
        "${_src_dir}/tools/rust/build_bindgen.py"

    sed -i 's/chrome-infra-packages.8pp2p8t.qjz9zk/chrome-infra-packages.appspot.com/g' \
        "${_src_dir}/tools/rust/build_rust.py"
}

setup_toolchain() {
    # Chromium currently has no non-x86 llvm/rust builds on
    # Linux, so we have to build it ourselves.
    if [ "$_host_arch" = x64 ]; then
        "${_src_dir}/tools/rust/update_rust.py"
        "${_src_dir}/tools/clang/scripts/update.py"
    else
        "${_src_dir}/tools/clang/scripts/build.py" \
            --without-fuchsia --without-android --disable-asserts \
            --host-cc=clang --host-cxx=clang++ --use-system-cmake \
            --with-ml-inliner-model=

        export CARGO_HOME="${_src_dir}/third_party/rust-src/cargo-home"
        "${_src_dir}/tools/rust/build_rust.py" \
            --skip-test

        "${_src_dir}/tools/rust/build_bindgen.py"
    fi

    if grep -q -F "use_sysroot=true" "${_out_dir}/args.gn"; then
        "${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py" --arch="$_host_arch" &
        if [ "$_build_arch" != "$_host_arch" ]; then
            "${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py" --arch="$_build_arch" &
        fi
        wait
    fi

    mkdir -p "${_src_dir}/third_party/node/linux/node-linux-x64/bin"
    ln -sf "$(which node)" "${_src_dir}/third_party/node/linux/node-linux-x64/bin/node"
    mkdir -p "${_src_dir}/third_party/gperf/cipd/bin/"
    ln -sf "$(which gperf)" "${_src_dir}/third_party/gperf/cipd/bin/gperf"
    mkdir -p "${_src_dir}/third_party/dawn/tools/golang/linux-amd64/bin"
    ln -sf "$(which go)" "${_src_dir}/third_party/dawn/tools/golang/linux-amd64/bin/go"

    # Same reasoning as node/gperf/go above, for a tool the tarball does not
    # carry either. src/DEPS pulls buildtools/linux64-format from a GCS bucket
    # - "linux64" for every Linux host, arm64 included, per its own condition -
    # and Chromium 152 made it load-bearing: crubit's support headers, which
    # chrome now depends on, are generated by an action that runs clang-format
    # over them. Without the binary ninja refuses the whole graph in its first
    # minute with "missing and no known rule to make it", which is how the
    # pre-flight found this.
    #
    # The system copy rather than the pinned one. clang-format only decides how
    # the generated header is laid out before it is compiled, so a version
    # difference changes whitespace in a file nobody reads and nothing else -
    # and a download would be a fourth thing to keep in step with a DEPS pin,
    # for that.
    if ! command -v clang-format >/dev/null; then
        echo "[aerium] FATAL: clang-format not found on PATH." >&2
        echo "[aerium]        It is generated-header formatting for crubit," >&2
        echo "[aerium]        needed by chrome since 152. Add the clang-format" >&2
        echo "[aerium]        package to docker/build.Dockerfile." >&2
        return 1
    fi
    mkdir -p "${_src_dir}/buildtools/linux64-format"
    ln -sf "$(command -v clang-format)" \
        "${_src_dir}/buildtools/linux64-format/clang-format"

    # xdg-mime/xdg-settings are genuine system utilities (from the xdg-utils
    # package) - Chromium only ever invokes them via PATH lookup at runtime
    # (see kXdgSettings in chrome/browser/shell_integration_linux.cc) and
    # never produces them under any ninja target, so package.sh's file list
    # can only be satisfied by vendoring the system copies into out/Default,
    # same as node/gperf above.
    cp "$(command -v xdg-mime)" "${_out_dir}/xdg-mime"
    cp "$(command -v xdg-settings)" "${_out_dir}/xdg-settings"

    local clang_bin="${_src_dir}/third_party/llvm-build/Release+Asserts/bin"
    export CC="${clang_bin}/clang"
    export CXX="${clang_bin}/clang++"
    export AR="${clang_bin}/llvm-ar"
    export NM="${clang_bin}/llvm-nm"
    export LLVM_BIN="${clang_bin}"

    local resource_dir
    resource_dir="$(${CC%% *} --print-resource-dir)"
    export CXXFLAGS+=" -resource-dir=${resource_dir} -B${LLVM_BIN}"
    export CPPFLAGS+=" -resource-dir=${resource_dir} -B${LLVM_BIN}"
    export CFLAGS+=" -resource-dir=${resource_dir} -B${LLVM_BIN}"
}

gn_gen() {
    cd "${_src_dir}"
    ./tools/gn/bootstrap/bootstrap.py -o out/Default/gn --skip-generate-buildfiles
    ./out/Default/gn gen out/Default --fail-on-unused-args
}

# Aerium: the GN targets this project owns, as label patterns for gn check.
#
# Deliberately not "everything". Chromium's .gn excludes only six v8 targets
# from header checking, so the rest of the tree is checkable in principle - but
# checking it would be slow and would surface upstream's problems, which are
# not ours to fix in a build script. This lists what Aerium adds.
#
# Not a standalone source_set of ours - there is none left since the content
# blocker was dropped - but the one upstream target Aerium adds includes to.
# chrome_browser_main_extra_parts_profiles.cc now includes
# chrome/browser/aerium/aerium_update_checker.h, which pulls in the network
# service, the JSON decoder and net/traffic_annotation, and the update patch
# declares those deps. This is what checks that it declared all of them.
_aerium_check_targets=(
    "//chrome/browser/profiles:profiles_extra_parts_impl"
)

# Aerium: verify that every #include in our own targets is covered by a
# declared dependency.
#
# This exists because a missing dep is close to invisible until it is
# expensive. //base does not public_dep :i18n, and //net does not include
# net/traffic_annotation, so a target using base/i18n/time_formatting.h or
# network_traffic_annotation.h without naming those deps builds fine right up
# until it does not - at link, hours in, or not at all on the machine where it
# was written. Both were real, in the content blocker, and neither was caught
# by anything before this.
#
# gn check is the right tool rather than a bespoke include scanner: it uses
# GN's own notion of what a dependency permits, including public_deps chains
# and allow_circular_includes_from, so it cannot drift from the build the way a
# hand-written parser would.
#
# Runs here, in the prepare phase, because gn gen has just finished and nothing
# has compiled yet. A failure costs the eight minutes already spent rather than
# the sixteen it takes to reach the first compile error, or the several hours
# to reach a link.
# Aerium: the ninja targets the pre-flight compiles.
#
# The point is a fast answer to "does the C++ we wrote actually compile", not a
# browser. A full build is 10+ hours and reports a syntax error in
# chrome/browser/browsing_data somewhere in hour six; these targets reach the
# same compiler over the same generated headers in a fraction of it.
#
# Object files rather than gn labels for the C++, because a source_set has no
# single ninja output to ask for - the objects are the artifact. The path is
# obj/<dir>/<target_name>/<file>.o, and the target name is the trap:
# chrome/browser/browsing_data/BUILD.gn declares TWO source_sets, and the .cc
# files live in "impl" while only the headers are in "browsing_data". Guessing
# the directory name is how run 3 of the pre-flight failed.
#
# build_ts is the TypeScript half and is worth more than it looks: it is the
# only place tsc sees settings/*.ts with Chromium's own config, so a WebUI
# element that type-checks locally against stubs still has to survive here.
# ESLint is a presubmit rather than a build step, so it is NOT covered.
#
# It is named by its manifest and not by a stamp because ts_library() is an
# action() with explicit outputs and produces no stamp - checked in
# tools/typescript/ts_library.gni rather than assumed, since the obvious guess
# is wrong and would have failed the first run with a puzzling message.
_aerium_preflight_targets=(
    "obj/chrome/browser/browsing_data/impl/aerium_site_rules.o"
    # Not Aerium-owned files, but the two upstream ones this project now adds
    # real code to: timezone_controller.cc carries the time zone override, and
    # about_flags.cc is where aerium_flag_entries.h and aerium_flag_choices.h
    # are #included and therefore where a typo in either surfaces.
    "obj/third_party/blink/renderer/core/core/timezone_controller.o"
    "obj/chrome/browser/browser/about_flags.o"
    "obj/chrome/browser/ui/ui/aerogel.o"
    "obj/chrome/browser/browsing_data/impl/chrome_browsing_data_lifetime_manager.o"
    "obj/chrome/browser/profiles/profiles_extra_parts_impl/chrome_browser_main_extra_parts_profiles.o"
    "gen/chrome/browser/resources/settings/build_ts_manifest.json"
)

# Aerium: compile just the Aerium-owned sources, and nothing else.
aerium_preflight() {
    cd "${_src_dir}"

    local target
    local -a missing=()
    for target in "${_aerium_preflight_targets[@]}"; do
        # A target that does not exist is not a pass - same reasoning as
        # gn_check_aerium above. Silently compiling nothing is how this rots
        # into a green tick that means nothing.
        if ! ninja -C out/Default -t query "${target}" >/dev/null 2>&1; then
            missing+=("${target}")
        fi
    done
    if [ "${#missing[@]}" -ne 0 ]; then
        echo "[aerium] FATAL: pre-flight targets are not in the build graph:" >&2
        local suggestion
        for target in "${missing[@]}"; do
            echo "[aerium]        ${target}" >&2
            # Almost always the gn target name in the path is wrong rather
            # than the file, so show what ninja does know by that basename.
            # Run 3 failed for exactly that and had to be diagnosed by reading
            # BUILD.gn by hand; this prints the answer instead.
            while read -r suggestion; do
                echo "[aerium]          did you mean: ${suggestion}" >&2
            done < <(ninja -C out/Default -t targets all 2>/dev/null \
                     | cut -d: -f1 \
                     | grep -F -- "$(basename "${target}")" \
                     | head -5)
        done
        echo "[aerium]        Fix _aerium_preflight_targets in scripts/shared.sh." >&2
        return 1
    fi

    local start elapsed
    start=$(date +%s)
    echo "[aerium] pre-flight: compiling ${#_aerium_preflight_targets[@]} targets"
    ninja -C out/Default "${_aerium_preflight_targets[@]}"
    elapsed=$(( $(date +%s) - start ))
    echo "[aerium] pre-flight compile finished in ${elapsed}s"
}

gn_check_aerium() {
    cd "${_src_dir}"

    if [ "${#_aerium_check_targets[@]}" -eq 0 ]; then
        echo "[aerium] gn check: no Aerium-owned targets to check"
        return 0
    fi

    local target rc=0
    for target in "${_aerium_check_targets[@]}"; do
        # A target that does not exist is not a pass. It means a patch that
        # was supposed to add it did not, and silently checking nothing is how
        # this kind of guard rots into decoration.
        if ! ./out/Default/gn ls out/Default "${target}" >/dev/null 2>&1; then
            echo "[aerium] FATAL: gn check target ${target} does not exist." >&2
            echo "[aerium]        A patch that should have created it did not apply." >&2
            return 1
        fi
        echo "[aerium] gn check ${target}"
        ./out/Default/gn check out/Default "${target}" || rc=1
    done

    if [ "${rc}" != 0 ]; then
        echo "[aerium] FATAL: gn check found includes with no declared dependency." >&2
        echo "[aerium]        Add the missing dep to the target's BUILD.gn." >&2
        return 1
    fi
    echo "[aerium] gn check clean"
}

maybe_build() {
    cd "${_src_dir}"
    # package.sh's file list also expects xdg-mime/xdg-settings out of
    # out/Default (used by the desktop default-browser/mime-handler
    # integration), but those are NOT separately nameable ninja targets -
    # they're produced as data dependencies while building "chrome" itself
    # (verified against upstream ungoogled-chromium-portablelinux's own
    # shared.sh, which builds only chrome+chromedriver and still packages
    # both files successfully). Asking ninja for "xdg_mime"/"xdg_settings"
    # by name fails with "unknown target" - there's nothing to add here.
    ninja -C out/Default chrome chromedriver
}
