<!--
SPDX-FileCopyrightText: 2026 Contributors to GAlMax

SPDX-License-Identifier: AGPL-3.0-or-later
-->

<p align="center">
  <img src="assets/logo/img/logo.png" width="120" alt="GAlMax logo" />
</p>

# GAlMax — Безопасный Matrix-мессенджер

[![Лицензия: AGPL v3](https://img.shields.io/badge/Лицензия-AGPLv3-blue.svg)](LICENSE)
[![Matrix](https://img.shields.io/badge/Matrix-совместим-brightgreen)](https://matrix.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter)](https://flutter.dev)
[![Демо](https://img.shields.io/badge/Демо-nightly-brightgreen?logo=github)](https://mrSaT13.github.io/GAlMax/nightly/)

[English](README.md) | **Русский**

Безопасный Matrix-клиент со сквозным шифрованием и звонками — форк [FluffyChat](https://github.com/krille-chan/fluffychat).

> **App ID:** `im.galmax.app` · **Лицензия:** `AGPL-3.0-or-later` · **Платформы:** Android, Web

> ⚠️ **Демо** [mrSaT13.github.io/GAlMax/nightly](https://mrSaT13.github.io/GAlMax/nightly/) — nightly-сборка только для предпросмотра, не используйте реальные пароли. Данные хранятся на вашем Matrix-сервере, а не на GitHub Pages.

---

### Возможности

- Сообщения Matrix: текст, файлы, фото, голосовые, шаринг локации
- Сквозное шифрование (Vodozemac), бэкап ключей, emoji-верификация
- Звонки (экспериментально, WebRTC)
- Пуши: FCM / UnifiedPush / фоновый опрос
- Избранное, стикеры, темы

### Скриншоты

> Добавить скриншоты в `assets/screenshots/` .

### Быстрый старт

Нужны [Flutter](https://flutter.dev) 3.44+ и Rust (для Vodozemac).

```sh
git clone https://github.com/mrSaT13/GAlMax.git
cd GAlMax
flutter pub get
flutter run
```

**Android:**
```sh
flutter build apk --release
# или: flutter build appbundle
```

**Web:**
```sh
./scripts/prepare-web.sh
flutter build web --release
```

Пример конфига: `config.sample.json`. Список серверов: `recommended_homeservers.json`.

### Настройка пушей

- Android FCM: файл `android/app/google-services.json` подается через секрет CI `GOOGLE_SERVICES_JSON` (см. `.github/workflows/release.yaml`), в репо не коммитится.
- UnifiedPush работает из коробки.
- Шлюз: `https://push.galmax.im/_matrix/push/v1/notify` (меняется в `lib/config/setting_keys.dart`).

### Структура проекта

- `lib/` — код приложения (Matrix SDK `matrix` ^7.2.4)
- `assets/stickers/galmax/` — в публичном репо заглушка (см. `assets/stickers/galmax/README.md`). Для локальной сборки восстановите CC0/CC-BY паки из `galmax-private`.
- `plugins/flutter_media_controller` — локальный форк, фикс SecurityException на старых MIUI.

### Лицензия и атрибуция

**AGPL-3.0-or-later** — см. [LICENSE](LICENSE).

Основано на [FluffyChat](https://github.com/krille-chan/fluffychat) © 2019-Present Christian Kußowski и контрибьюторы. Модификации © 2024-2026 GAlMax Contributors.

Стикеры/звуки: см. `REUSE.toml` и `LICENSES/`. В публичном репо несвободные стикеры удалены.

### Приватность

См. [PRIVACY.md](PRIVACY.md). Без трекинга, данные хранятся на вашем Matrix-сервере.

### Участие

См. [CONTRIBUTING.md](CONTRIBUTING.md). PR приветствуются — сохраняйте заголовки `AGPL-3.0`.

### Безопасность

См. [SECURITY.md](SECURITY.md) для сообщения об уязвимостях.
