# Updating Aerium (Linux)

How to move Aerium onto a newer Chromium/ungoogled-chromium release.

## Where things live

- **Base**: `ungoogled-chromium` submodule (the same core project the Windows repo uses — Windows and Linux share the identical core-patch dependency chain; Android's Vanadium is unrelated) + this repo's Linux/AppImage packaging, forked from `ungoogled-software/ungoogled-chromium-portablelinux`. Chromium version is tracked in `ungoogled-chromium/chromium_version.txt`.
- **Our changes**: `scripts/apply_branding.py` (Chromium→Aerium string sweep + `BRANDING` file rewrite + logo swap — ported from the Windows repo's `build.py:_apply_branding()`, minus the Windows-only install-mode-constants step), wired into `scripts/shared.sh`'s `apply_branding()` (called from both `scripts/build.sh` and `.github/scripts/build.sh`, between `apply_domsub` and `write_gn_args` — must stay after domain substitution and before `gn_gen`, same ordering Windows uses and for the same reason: it operates on final pre-build text), `brand/` (logo assets, copied from the Windows repo's `brand/`), `package/aerium.desktop` (renamed+rebranded from upstream's `ungoogled-chromium.desktop` — the `Exec=chromium` lines are deliberately left literal, `scripts/package.sh`'s existing sed rewrites them to `Exec=AppRun` regardless of app-name branding), `scripts/package.sh`'s `_app_name`/AppDir path/icon renames and the `_update_info` zsync URL (repointed to this repo — **critical**, see below), `patches/aerium-fatih/` (Aerium's own privacy-default patches, once ported — see the "8 patches" section), the converted CI trigger (`.github/workflows/build.yml` — push+`workflow_dispatch` instead of upstream's tag-only trigger, see the commit that made this change for the reasoning).

## Sync procedure

Upstream (`ungoogled-software/ungoogled-chromium-portablelinux`) uses normal PRs, so a merge is safe here — same situation as the Windows repo, not Android's force-push situation.

1. `git remote add upstream https://github.com/ungoogled-software/ungoogled-chromium-portablelinux.git` (once)
2. `git fetch upstream && git merge upstream/master`
3. Resolve conflicts. Files most likely to conflict, and which side to prefer:
   - `.github/workflows/build.yml` — keep ours (the push+workflow_dispatch conversion is a deliberate, permanent divergence from upstream's tag-only trigger — re-apply it if upstream's own workflow changes underneath).
   - `scripts/shared.sh` — keep the `apply_branding()` function and its call site in `scripts/build.sh`/`.github/scripts/build.sh`; take upstream's changes to everything else in these files.
   - `scripts/package.sh` — keep the `aerium`/`aerium-browser`/`aerium-browser-linux` renames; take upstream's changes to the file list, AppDir layout, or packaging logic itself.
   - `.github/actions/package/action.yml`, `.github/actions/release/action.yml` — keep the `aerium-*` artifact-name/glob renames; take upstream's changes to the steps themselves.
4. Bump the submodule if the merge didn't already move it: `git -C ungoogled-chromium fetch --tags && git -C ungoogled-chromium checkout <tag>`.
5. Verify the 8 `patches/aerium-fatih/*.patch` files still apply, once they exist — dry-run each against a scratch checkout of the new Chromium source, same method as the Windows repo's `UPDATING.md`. Three of the eight (`aerium-first-run-page.patch`, `aerium-widevine-toggle.patch`, `aerium-search-engines.patch`) depend on one of the *core* `ungoogled-chromium` submodule's own `extra/` patches being applied first (`first-run-page.patch`, `add-flags-for-existing-switches.patch`, and the search-engines JSON's DEPS-pinned revision respectively) — regenerate against the state *after* those core patches, not raw pristine Chromium, using the same reconstruct-then-diff method documented in the Windows repo's `UPDATING.md`.
6. Commit, then dispatch **Build** (`workflow_dispatch`, leave `resume_run_id` empty for a version bump — a bumped Chromium source invalidates any old run's build-cache anyway).
7. When green, the `release` job publishes automatically.

## The `aerium-fatih` patches — porting status

Windows's `patches/ungoogled-fatih/*.patch` are all pure Blink/content/chrome/components C++ or JSON — none touch Windows-only code (that lives separately in Windows's `build.py`/`package.py`, not in the patches themselves), so they port with minimal adaptation.

**Ported and in `patches/series`** (identical files to the Windows repo, verified to apply against Chromium 150.0.7871.186 after the core ungoogled-chromium patch set):

- `aerium-first-run-page.patch`
- `aerium-first-run-url-rename.patch`
- `default-flags.patch`
- `aerium-battery-efficiency.patch`
- `aerium-https-first-balanced.patch`
- `aerium-global-privacy-control.patch`
- `aerium-widevine-toggle.patch`
- `aerium-search-engines.patch`

Because these files are byte-identical across the two repos, a regeneration for a new Chromium tag only has to be done once — do it in the Windows repo and copy the result here (or the reverse), rather than maintaining two diverging copies.

**Deliberately not ported:**

- **`bundled-external-extensions.patch`** — it adds its provider inside the Windows-only branch of `external_provider_impl.cc` and relies on `chrome::DIR_EXTERNAL_EXTENSIONS` resolving next to the main binary. Inside an AppImage's read-only, FUSE-mounted AppDir that needs verifying against the actual runtime layout (`opt/aerium/chrome`, per `scripts/package.sh`'s `AppRun`), and the `extensions/` directory would need adding to `scripts/package.sh`'s fixed `_files` list. Verify by actually running a locally-built AppImage with a bundled extension present, not just by confirming the patch applies. Until then the Linux README must not claim Chrome Web Store availability.

**Known adaptation point still open:**

- **`aerium-first-run-page.patch`** deliberately deletes the pre-existing Linux dictionary-path line (`~/.config/chromium/Dictionaries/`) from ungoogled-chromium's own upstream `first-run-page.patch`, keeping only a rewritten Windows line. The correct Linux fix is to *restore* a rebranded Linux line, not to invent one — the patch as copied still carries the Windows-only text.

## When a patch fails to apply

A bumped Chromium often moves code a patch targets, so `patches.py apply` fails on a hunk. Open the target file at the new Chromium tag on `https://chromium.googlesource.com/chromium/src/+/refs/tags/<version>/<path>`, find the moved code, and regenerate the patch against it — same method as both sibling repos.

## Chromium build-cache mechanism (this repo only)

Unlike Windows/Android, this pipeline's `prep` job *always* does a fresh source checkout+patch+`gn gen` on every run — there's no "fresh vs resume" toggle at that level, it's upstream's own design. What's resumable across runs is the multi-hour `ninja` compile itself, via `resume_run_id` (a `workflow_dispatch` input, wired through to `build_part_01` only). See the commit that added CI-trigger conversion for the full reasoning, and the Windows repo's `UPDATING.md` "When a stage dies with no log at all" section for how to tell a genuine runner death apart from the internal 5-hour-per-part `timeout` firing normally (the latter logs a clean message; the former leaves no trace).
