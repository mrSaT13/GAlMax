// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:async/async.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),

  /// Max lines for unselected HTML/text bubbles; 0 = unlimited (no fade).
  messagePreviewMaxLines<int>('im.galmax.message_preview_max_lines', 25),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 44100),
  showNoGoogle<bool>('im.galmax.show_no_google', false),
  unifiedPushRegistered<bool>('im.galmax.unifiedpush.registered', false),
  unifiedPushEndpoint<String>('im.galmax.unifiedpush.endpoint', ''),
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    'https://push.galmax.im/_matrix/push/v1/notify',
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  renderHtml<bool>('im.galmax.renderHtml', true),
  fontSizeFactor<double>('im.galmax.font_size_factor', 1.0),
  hideRedactedEvents<bool>('im.galmax.hideRedactedEvents', false),
  hideUnknownEvents<bool>('im.galmax.hideUnknownEvents', true),
  autoplayImages<bool>('im.galmax.autoplay_images', true),
  sendTypingNotifications<bool>('im.galmax.send_typing_notifications', true),
  sendPublicReadReceipts<bool>('im.galmax.send_public_read_receipts', true),
  swipeRightToLeftToReply<bool>('im.galmax.swipeRightToLeftToReply', true),
  sendOnEnter<bool>('im.galmax.send_on_enter', false),
  displayNavigationRail<bool>('im.galmax.display_navigation_rail', false),
  experimentalVoip<bool>('im.galmax.experimental_voip', true),
  shareKeysWith<String>('im.galmax.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>(
    'im.galmax.no_encryption_warning_shown',
    false,
  ),
  displayChatDetailsColumn('im.galmax.display_chat_details_column', false),
  // AppConfig-mirrored settings
  applicationName<String>('im.galmax.application_name', 'GAlMax'),
  defaultHomeserver<String>('im.galmax.default_homeserver', 'matrix.org'),
  // colorSchemeSeed stored as ARGB int
  colorSchemeSeedInt<int>('im.galmax.color_scheme_seed', 0xFF5625BA),
  emojiSuggestionLocale<String>('emoji_suggestion_locale', ''),
  cornerRadius<double>('im.galmax.corner_radius', 18.0),
  enableSoftLogout<bool>('im.galmax.enable_soft_logout', false),
  enableMatrixNativeOIDC<bool>('im.galmax.enable_matrix_native_oidc', false),
  presetHomeserver<String>('im.galmax.preset_homeserver', ''),
  welcomeText<String>('im.galmax.welcome_text', ''),
  website<String>('im.galmax.website_url', 'https://galmax.im'),
  logoUrl<String>(
    'im.galmax.logo_url',
    'https://galmax.im/assets/favicon.png',
  ),
  privacyPolicy<String>(
    'im.galmax.privacy_policy_url',
    'https://galmax.im/en/privacy',
  ),
  tos<String>('im.galmax.tos_url', 'https://galmax.im/en/tos'),
  sendTimelineEventTimeout<int>('im.galmax.send_timeline_event_timeout', 15),
  webNotificationSound<bool>('im.galmax.web_notification_sound', true),
  notificationSoundEnabled<bool>('im.galmax.notification_sound', true),
  notificationSoundName<String>(
    'im.galmax.notification_sound_name',
    'notification',
  ),
  chatLocalBackgroundPath<String>('im.galmax.chat_background_path', ''),
  chatLocalBackgroundOpacity<double>(
    'im.galmax.chat_background_opacity',
    0.35,
  ),
  chatLocalBackgroundBlur<double>('im.galmax.chat_background_blur', 0.0),
  biometricUnlock<bool>('im.galmax.biometric_unlock', false),
  transportMimicry<bool>('im.galmax.transport_mimicry', false),
  mimicryLevel<int>('im.galmax.mimicry_level', 1),
  chatFilter<String>('im.galmax.chat_filter', 'allChats'),
  hideRoomsInSpaces<bool>('im.galmax.hideRoomsInSpaces', false),
  showThumbnailsInTimeline<bool>('im.galmax.showThumbnailsInTimeline', true),
  backgroundSyncIntervalMinutes<int>('im.galmax.background_sync_interval', 15),
  // Избранное: 'server' — комната с собой (синхронизируется),
  // 'local' — только на этом устройстве.
  favoritesMode<String>('im.galmax.favorites_mode', 'server'),
  // Показывать ли плитку «Избранное» над списком чатов.
  // Выключено — Избранное полностью скрыто (и плитка, и комната-дубль).
  showFavoritesTile<bool>('im.galmax.show_favorites_tile', true),
  // Live-гео серией m.location: false = каждая точка отдельным пузырём
  // (стандартно, видно везде), true = склеивать серию в один трек-маршрут.
  groupLiveLocations<bool>('im.galmax.group_live_locations', false),
  broadcastMusicPresence<bool>('im.galmax.broadcast_music_presence', false),
  broadcastMusicPreviousStatus<String>('im.galmax.broadcast_music_prev', ''),
  debugPush<bool>('im.galmax.debug_push', false);

  final String key;
  final T defaultValue;

  const AppSettings(this.key, this.defaultValue);

  static SharedPreferences get store => _store!;
  static SharedPreferences? _store;

  static Future<void> reset({bool loadWebConfigFile = true}) async {
    await AppSettings._store!.clear();
    await init(loadWebConfigFile: loadWebConfigFile);
  }

  static Future<SharedPreferences> init({bool loadWebConfigFile = true}) async {
    if (AppSettings._store != null) return AppSettings.store;

    final store = AppSettings._store = await SharedPreferences.getInstance();

    // Migrate legacy chat.fluffy.* keys to im.galmax.* (one-time, keeps user settings)
    for (final setting in AppSettings.values) {
      if (!setting.key.startsWith('im.galmax.')) continue;
      if (store.get(setting.key) != null) continue;
      final legacyKey = setting.key.replaceFirst('im.galmax.', 'chat.fluffy.');
      final legacyValue = store.get(legacyKey);
      if (legacyValue == null) continue;
      if (legacyValue is bool) {
        await store.setBool(setting.key, legacyValue);
      } else if (legacyValue is String) {
        await store.setString(setting.key, legacyValue);
      } else if (legacyValue is int) {
        await store.setInt(setting.key, legacyValue);
      } else if (legacyValue is double) {
        await store.setDouble(setting.key, legacyValue);
      }
      await store.remove(legacyKey);
    }

    // Миграция старого названия 'galmax' -> 'GAlMax' для существующих установок.
    // Ключ im.galmax.application_name виден в интерфейсе (заголовок, About,
    // пуши), поэтому правим только точное совпадение нижнего регистра,
    // пользовательские кастомные названия не трогаем.
    try {
      if (store.getString(AppSettings.applicationName.key) == 'galmax') {
        await store.setString(AppSettings.applicationName.key, 'GAlMax');
      }
    } catch (_) {}

    // Migrate wrong datatype for fontSizeFactor
    final fontSizeFactorString = Result(
      () => store.getString(AppSettings.fontSizeFactor.key),
    ).asValue?.value;
    if (fontSizeFactorString != null) {
      Logs().i('Migrate wrong datatype for fontSizeFactor!');
      await store.remove(AppSettings.fontSizeFactor.key);
      final fontSizeFactor = double.tryParse(fontSizeFactorString);
      if (fontSizeFactor != null) {
        await store.setDouble(AppSettings.fontSizeFactor.key, fontSizeFactor);
      }
    }

    if (store.getBool(AppSettings.sendOnEnter.key) == null) {
      await store.setBool(AppSettings.sendOnEnter.key, !PlatformInfos.isMobile);
    }
    if (kIsWeb && loadWebConfigFile) {
      try {
        final configJsonString = utf8.decode(
          (await http.get(Uri.parse('config.json'))).bodyBytes,
        );
        final configJson =
            json.decode(configJsonString) as Map<String, Object?>;
        for (final setting in AppSettings.values) {
          if (store.get(setting.key) != null) continue;
          final configValue = configJson[setting.name];
          if (configValue == null) continue;
          if (configValue is bool) {
            await store.setBool(setting.key, configValue);
          }
          if (configValue is String) {
            await store.setString(setting.key, configValue);
          }
          if (configValue is int) {
            await store.setInt(setting.key, configValue);
          }
          if (configValue is double) {
            await store.setDouble(setting.key, configValue);
          }
        }
      } on FormatException catch (_) {
        Logs().v('[ConfigLoader] config.json not found');
      } catch (e) {
        Logs().v('[ConfigLoader] config.json not found', e);
      }
    }

    return store;
  }
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsStringExtension on AppSettings<String> {
  String get value {
    final value = Result(() => AppSettings.store.getString(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(String value) => AppSettings.store.setString(key, value);
}

extension AppSettingsIntExtension on AppSettings<int> {
  int get value {
    final value = Result(() => AppSettings.store.getInt(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(int value) => AppSettings.store.setInt(key, value);
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double get value {
    final value = Result(() => AppSettings.store.getDouble(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(double value) => AppSettings.store.setDouble(key, value);
}
