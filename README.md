<p align="center">
  <img src="brand/product_logo.svg" width="96" height="96" alt="Aerium logo">
</p>

<h1 align="center">Aerium</h1>

<p align="center"><i>by Dioide</i></p>

[![build](https://img.shields.io/github/actions/workflow/status/fatih-gh/aerium-browser-linux/build.yml?label=build)](https://github.com/fatih-gh/aerium-browser-linux/actions/workflows/build.yml)
[![release](https://img.shields.io/github/v/release/fatih-gh/aerium-browser-linux)](https://github.com/fatih-gh/aerium-browser-linux/releases/latest)

Aerium is a browser for people who'd rather their browser stayed out of the way. No telemetry calling home, no bundled Google services, no ad platform baked into the settings page.

[**Download for Linux**](https://github.com/fatih-gh/aerium-browser-linux/releases/latest) (x86_64 and arm64 AppImages)

## Running it

AppImages don't need installing:

```sh
chmod +x aerium-*.AppImage
./aerium-*.AppImage
```

The AppImage self-updates in place (via [zsync](https://github.com/AppImage/AppImageUpdate)) once a newer release is out, if you use an AppImage-aware launcher — otherwise, just re-download.

## What you get

- **Its own name, its own icon — your own colors.** The appearance picker in Settings works exactly like it does in stock Chromium; nothing forces a palette on top of it.
- **Privacy defaults you don't have to hunt for.** Fingerprinting resistance, minimal referrers, reduced system info, and a handful of others are on from the start. Nothing's locked — change any of it in `chrome://flags` and it behaves like flags always have.
- **HTTPS by default.** Balanced Mode upgrades navigations to HTTPS automatically, without the disruptive full-site warnings of strict HTTPS-only enforcement.
- **Global Privacy Control sent by default.** The `Sec-GPC` opt-out signal and `navigator.globalPrivacyControl` — recognized under CCPA, but still not implemented in stock Chromium — are on for every page, no toggle needed.
- **A first-run page that's actually useful.** Recommendations for an ad blocker, a bookmark sync tool, and a new-tab replacement — all free and open-source, none of them installed for you.
- **Lighter by default.** The name comes from aerogel, the lightest solid there is — battery and resource efficiency are a brand commitment here, not an afterthought.
- **DRM off by default, your call either way.** Widevine isn't registered unless you turn it on at `chrome://flags/#enable-widevine`.

## Building

Every push to `master` builds automatically on GitHub Actions, using Docker-based build/package environments — no host-OS toolchain setup needed. A full build takes several hours across both architectures (arm64 and x86_64, built in parallel). Every finished build is published as a release.

Want your own build? Fork the repo, install Docker, and run `scripts/docker-build.sh` followed by `package/docker-package.sh` — see [the upstream project's build docs](https://github.com/ungoogled-software/ungoogled-chromium-portablelinux#building) for the underlying mechanics, unchanged here beyond branding.

## Contributing

Issues and pull requests are welcome. See [UPDATING.md](UPDATING.md) for how the build stays in sync with upstream Chromium releases.

## About

Aerium is built on [Chromium](https://www.chromium.org/) via [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium), packaged as a portable AppImage using [ungoogled-chromium-portablelinux](https://github.com/ungoogled-software/ungoogled-chromium-portablelinux)'s build system, with Aerium's own branding and defaults layered on top. Licensed under Chromium's BSD-style license — see [LICENSE](LICENSE).
