<p align="center">
  <img src="brand/product_logo.svg" width="96" height="96" alt="Aerium logo">
</p>

<h1 align="center">Aerium</h1>

<p align="center"><i>by Dioide</i></p>

[![release](https://img.shields.io/github/v/release/aerium-browser/aerium-browser-linux)](https://github.com/aerium-browser/aerium-browser-linux/releases/latest)
[![released](https://img.shields.io/github/release-date/aerium-browser/aerium-browser-linux?label=released)](https://github.com/aerium-browser/aerium-browser-linux/releases/latest)
[![downloads](https://img.shields.io/github/downloads/aerium-browser/aerium-browser-linux/total?label=downloads)](https://github.com/aerium-browser/aerium-browser-linux/releases)

Aerium is a browser for people who'd rather their browser stayed out of the way. No telemetry calling home, no bundled Google services, no ad platform baked into the settings page.

[**Download for Linux**](https://github.com/aerium-browser/aerium-browser-linux/releases/latest) (x86_64 and arm64 AppImages)

## Running it

AppImages don't need installing:

```sh
chmod +x aerium-*.AppImage
./aerium-*.AppImage
```

The AppImage self-updates in place (via [zsync](https://github.com/AppImage/AppImageUpdate)) once a newer release is out, if you use an AppImage-aware launcher — otherwise, just re-download.

## What you get

- **Its own name, its own icon — your own colors.** The appearance picker in Settings works exactly like it does in stock Chromium; nothing forces a palette on top of it.
- **Search that works from the first keystroke.** DuckDuckGo is the default engine, with Startpage, Brave Search, Mojeek, Qwant, Ecosia, degoog and the two DuckDuckGo no-JS variants ready to pick in Settings — and any other engine addable by hand.
- **Privacy defaults you don't have to hunt for.** Minimal referrers and a handful of others are on from the start. Fingerprinting resistance, reduced system info, and more are one click away in `chrome://flags` instead of silently defaulted — see the first-run page for the full list.
- **HTTPS by default.** Balanced Mode upgrades navigations to HTTPS automatically, without the disruptive full-site warnings of strict HTTPS-only enforcement.
- **Global Privacy Control sent by default.** The `Sec-GPC` opt-out signal and `navigator.globalPrivacyControl` — recognized under CCPA, but still not implemented in stock Chromium — are on for every page, no toggle needed.
- **A first-run page that's actually useful.** Recommendations for an ad blocker, a bookmark sync tool, and a new-tab replacement — all free and open-source, none of them installed for you.
- **Lighter by default.** Memory Saver and Battery Saver are on out of the box, and a handful of background network chatter — hint prefetching, domain reliability pings — is off. The name comes from aerogel, the lightest solid there is.
- **DRM off by default, your call either way.** Widevine isn't registered unless you turn it on at `chrome://flags/#enable-widevine`.

- **Aerogel tabs.** A tab with a cookie jar of its own, from the app menu or by right-clicking a link. Sign in to a second account on a site you are already signed in to, or open a link without handing it to the profile that knows you. The jar is never written to disk and is emptied when the tab closes. It is not Incognito: your history still records where you went, which is the point — this separates identity, not traces.

## Building

Every push to `master` builds automatically on GitHub Actions, using Docker-based build/package environments — no host-OS toolchain setup needed. A full build takes several hours across both architectures (arm64 and x86_64, built in parallel). Every finished build is published as a release.

Want your own build? Fork the repo, install Docker, and run `scripts/docker-build.sh` followed by `package/docker-package.sh` — see [the upstream project's build docs](https://github.com/ungoogled-software/ungoogled-chromium-portablelinux#building) for the underlying mechanics, unchanged here beyond branding.

## Contributing

Issues and pull requests are welcome. See [UPDATING.md](UPDATING.md) for how the build stays in sync with upstream Chromium releases.

## About

Aerium is built on [Chromium](https://www.chromium.org/) via [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium), packaged as a portable AppImage using [ungoogled-chromium-portablelinux](https://github.com/ungoogled-software/ungoogled-chromium-portablelinux)'s build system, with Aerium's own branding and defaults layered on top. Licensed under Chromium's BSD-style license — see [LICENSE](LICENSE).
