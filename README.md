<!--
SPDX-FileCopyrightText: 2026 Contributors to GAlMax

SPDX-License-Identifier: AGPL-3.0-or-later
-->

<p align="center">
  <img src="assets/logo/img/logo.png" width="120" alt="GAlMax logo" />
</p>

# GAlMax — Secure Matrix Messenger

[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](LICENSE)
[![Matrix](https://img.shields.io/badge/Matrix-compatible-brightgreen)](https://matrix.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter)](https://flutter.dev)
[![Demo](https://img.shields.io/badge/Demo-nightly-brightgreen?logo=github)](https://mrSaT13.github.io/GAlMax/nightly/)

**English** | [Русский](README_RU.md)

Secure Matrix client with end-to-end encryption and calls — fork of [FluffyChat](https://github.com/krille-chan/fluffychat).

> **App ID:** `im.galmax.app` · **License:** `AGPL-3.0-or-later` · **Platforms:** Android, Web

---

### Features

- Matrix messaging: text, files, images, voice, location sharing
- End-to-end encryption (Vodozemac), key backup, emoji verification
- Calls (experimental, WebRTC)
- Push: FCM / UnifiedPush / background polling
- Favorites, stickers, themes

### Screenshots



### Quick Start

Requires [Flutter](https://flutter.dev) 3.44+ and Rust (for Vodozemac).

```sh
git clone https://github.com/mrSaT13/GAlMax.git
cd GAlMax
flutter pub get
flutter run
```

**Android:**
```sh
flutter build apk --release
# or: flutter build appbundle
```

**Web:**
```sh
./scripts/prepare-web.sh
flutter build web --release
```

Config example: `config.sample.json`. Homeservers: `recommended_homeservers.json`.

### Push Setup

- Android FCM: provide `android/app/google-services.json` via CI secret `GOOGLE_SERVICES_JSON` (see `.github/workflows/release.yaml`). Not committed.
- UnifiedPush supported out of the box.
- Gateway: `https://push.galmax.im/_matrix/push/v1/notify` (configurable in `lib/config/setting_keys.dart`).

### Project Structure

- `lib/` — app code (Matrix SDK `matrix` ^7.2.4)
- `assets/stickers/galmax/` — placeholder in public repo (see `assets/stickers/galmax/README.md`). Restore CC0/CC-BY packs for local build.
- `plugins/flutter_media_controller` — local fork, fixes SecurityException on old MIUI.

### License & Attribution

**AGPL-3.0-or-later** — see [LICENSE](LICENSE).

Based on [FluffyChat](https://github.com/krille-chan/fluffychat) © 2019-Present Christian Kußowski and contributors. Modifications © 2024-2026 GAlMax Contributors.

Stickers/sounds: see `REUSE.toml` and `LICENSES/`. Public repo ships without non-free stickers.

### Privacy

See [PRIVACY.md](PRIVACY.md). No tracking. Data stays on your Matrix homeserver.

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). PRs welcome — please keep `AGPL-3.0` headers.

### Security

See [SECURITY.md](SECURITY.md) to report vulnerabilities.
