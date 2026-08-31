#!/bin/bash
set -euo pipefail

_current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
_root_dir="$(cd "$_current_dir/.." && pwd)"
_build_dir="$_root_dir/build"
_release_dir="$_build_dir/release"
_app_dir="$_release_dir/aerium.AppDir"

_chromium_version=$(cat "$_root_dir/ungoogled-chromium/chromium_version.txt")
_ungoogled_revision=$(cat "$_root_dir/ungoogled-chromium/revision.txt")

_app_name="aerium"
_version="$_chromium_version-$_ungoogled_revision"

_arch=$(cat "$_build_dir/src/out/Default/args.gn" \
                | grep ^target_cpu \
                | tail -1 \
                | sed 's/.*=//' \
                | cut -d'"' -f2)

if [ "$_arch" = "x64" ]; then
    _arch="x86_64"
fi

_release_name="$_app_name-$_version-$_arch"
# gh-releases-zsync update info: MUST point at Aerium's own repo, not
# upstream's - appimagetool bakes this into the AppImage's self-update
# metadata, and a stale pointer silently offers/pulls updates from the
# wrong project.
_update_info="gh-releases-zsync|aerium-browser|aerium-browser-linux|latest|$_app_name-*-$_arch.AppImage.zsync"
_tarball_name="${_release_name}_linux"
_tarball_dir="$_release_dir/$_tarball_name"

# Chromium Web Store extension (https://github.com/NeverDecaf/chromium-web-store).
# chrome::DIR_EXTERNAL_EXTENSIONS resolves to DIR_MODULE/extensions on Linux
# (chrome/common/chrome_paths.cc) with no admin/root ownership requirement,
# and stock Chromium already scans that directory for external-pref JSON
# files (chrome/browser/extensions/external_provider_impl.cc's non-Windows
# branch) - so unlike Windows this needs no source patch, just the crx and
# a manifest staged into out/Default/extensions before packaging.
_cws_id="ocaahdebbfolfmndjeplogmgcagdmblk"
_cws_version="1.5.5.3"
_cws_sha256="326443baec3d204b1358eba6aa025cf6bd930c08a0b98f6784e7a3236528445b"
_cws_dir="$_build_dir/src/out/Default/extensions"
mkdir -p "$_cws_dir"
if [ ! -f "$_cws_dir/chromium_web_store.crx" ]; then
    curl -sSL -o "$_cws_dir/chromium_web_store.crx" \
        "https://github.com/NeverDecaf/chromium-web-store/releases/download/v${_cws_version}/Chromium.Web.Store.crx"
fi
echo "${_cws_sha256}  ${_cws_dir}/chromium_web_store.crx" | sha256sum -c -
cat > "$_cws_dir/chromium_web_store.json" <<EOF
{
  "${_cws_id}": {
    "external_crx": "chromium_web_store.crx",
    "external_version": "${_cws_version}"
  }
}
EOF

# product_logo_256.png is only needed for the AppImage's hicolor icon, not
# by the browser itself, so it isn't guaranteed to land in out/Default -
# copy it straight from the repo's own branded source instead (identical
# bytes to what apply_branding.py staged into the chromium tree).
_files="chrome
chrome_100_percent.pak
chrome_200_percent.pak
chrome_crashpad_handler
chromedriver
chrome-wrapper
extensions/
icudtl.dat
libEGL.so
libGLESv2.so
libqt5_shim.so
libqt6_shim.so
libvk_swiftshader.so
libvulkan.so.1
locales/
product_logo_48.png
resources.pak
v8_context_snapshot.bin
vk_swiftshader_icd.json
xdg-mime
xdg-settings"

echo "copying release files and creating $_tarball_name.tar.xz"

mkdir -p "$_tarball_dir"

# These copies run in parallel, so `set -e` does not see their exit codes -
# collect the PIDs and wait on each one individually, otherwise a missing
# build output (e.g. a target that silently didn't get built) just produces
# an AppImage with a file quietly absent from it.
_copy_pids=()
for file in $_files; do
    cp -r "$_build_dir/src/out/Default/$file" "$_tarball_dir" &
    _copy_pids+=("$!")
done
cp "$_root_dir/brand/product_logo_256.png" "$_tarball_dir" &
_copy_pids+=("$!")

for _pid in "${_copy_pids[@]}"; do
    if ! wait "$_pid"; then
        echo "error: a release file failed to copy - aborting packaging" >&2
        exit 1
    fi
done

_size="$(du -sk "$_tarball_dir" | cut -f1)"

pushd "$_release_dir"

tar vcf - "$_tarball_name" \
    | pv -s"${_size}k" \
    | xz -e9 > "$_release_dir/$_tarball_name.tar.xz" &

# create AppImage
rm -rf "$_app_dir"
mkdir -p "$_app_dir/opt/aerium/" "$_app_dir/usr/share/icons/hicolor/48x48/apps/" "$_app_dir/usr/share/icons/hicolor/256x256/apps/"
cp -r "$_tarball_dir"/* "$_app_dir/opt/aerium/"
cp "$_root_dir/package/aerium.desktop" "$_app_dir"
# The .desktop's Exec= line is deliberately left as "Exec=chromium %U" in the
# source file (see package/aerium.desktop) so this sed keeps matching
# regardless of app-name rebranding - it's rewritten to point at the
# AppImage's own AppRun entrypoint either way.
sed -i -e 's|Exec=chromium|Exec=AppRun|g' "$_app_dir/aerium.desktop"

cat > "$_app_dir/AppRun" <<'EOF'
#!/bin/sh
THIS="$(readlink -f "${0}")"
HERE="$(dirname "${THIS}")"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export CHROME_WRAPPER="${THIS}"
"${HERE}"/opt/aerium/chrome "$@"
EOF
chmod a+x "$_app_dir/AppRun"

cp "${_app_dir}/opt/aerium/product_logo_48.png" "$_app_dir/usr/share/icons/hicolor/48x48/apps/aerium.png"
cp "${_app_dir}/opt/aerium/product_logo_256.png" "$_app_dir/usr/share/icons/hicolor/256x256/apps/aerium.png"
cp "${_app_dir}/usr/share/icons/hicolor/256x256/apps/aerium.png" "$_app_dir"

export APPIMAGETOOL_APP_NAME="$_app_name"
export VERSION="$_version"

appimagetool \
    -u "$_update_info" \
    "$_app_dir" \
    "$_release_name.AppImage" &
popd
wait

rm -rf "$_tarball_dir" "$_app_dir"
