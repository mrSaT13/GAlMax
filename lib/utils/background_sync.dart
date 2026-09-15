// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/chat/scheduled_messages.dart';
import 'package:galmax/utils/client_manager.dart';
import 'package:galmax/utils/cross_isolate_mutex.dart';
import 'package:galmax/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/utils/push_helper.dart';
import 'package:galmax/utils/transport_mimicry.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entry point for the foreground-service isolate. Must be top-level.
@pragma('vm:entry-point')
void galmaxSyncTaskStarter() {
  FlutterForegroundTask.setTaskHandler(_GalmaxSyncTaskHandler());
}

class _GalmaxSyncTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Fire and forget: sync errors are logged inside.
    BackgroundSyncService.performSync();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Результат одной проверки: сколько клиентов/комнат реально опрошено
/// и сколько уведомлений показано. Пустой `error` = без ошибок.
/// `skipped` = вызов пропущен из-за параллельного синка.
class BackgroundSyncReport {
  final int clientsChecked;
  final int roomsScanned;
  final int notified;
  final String? error;
  final bool skipped;

  const BackgroundSyncReport({
    this.clientsChecked = 0,
    this.roomsScanned = 0,
    this.notified = 0,
    this.error,
    this.skipped = false,
  });
}

/// Periodic Matrix sync that works even when the app is swiped away.
/// Fallback for when FCM and UnifiedPush are not available.
///
/// Two layers:
/// 1. In-app [Timer] while the app process is alive (foreground).
/// 2. A foreground service (Android) that survives app swipes and
///    syncs every 15 minutes. Requires the persistent notification.
class BackgroundSyncService {
  static BackgroundSyncService? _instance;
  factory BackgroundSyncService() => _instance ??= BackgroundSyncService._();
  BackgroundSyncService._();

  static const String _enabledKey = 'im.galmax.background_sync_enabled';
  static const String _serviceChannelId = 'galmax_sync';

  /// Интервал опроса, настраивается в Настройки → Уведомления
  /// (1/2/5/15/30 мин). Как в SchildiChat: короткий интервал = тот же
  /// foreground-сервис, просто чаще дёргает sync. Цена — батарея.
  static Duration get interval =>
      Duration(minutes: AppSettings.backgroundSyncIntervalMinutes.value);

  bool _initialized = false;
  Timer? _syncTimer;

  static Future<bool> isEnabled() async {
    try {
      final store = await SharedPreferences.getInstance();
      return store.getBool(_enabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setBool(_enabledKey, value);
    } catch (_) {}
    if (value) {
      await BackgroundSyncService().ensureRunning();
    } else {
      await BackgroundSyncService().stop();
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Layer 1: in-app timer (works while the process is alive).
    // При включённой маскировке интервал плавает 12–19 мин вместо ровных 15.
    _syncTimer = Timer.periodic(interval, (_) {
      performSync();
      if (TransportMimicry.instance.enabled) _rejitterTimer();
    });

    // Layer 2: foreground service (survives app swipes on Android).
    await ensureRunning();
    Logs().i('[BackgroundSync] Initialized (timer + foreground service)');
  }

  void _rejitterTimer() {
    // Пересоздаём таймер со случайным интервалом ±25% от базового,
    // минимум 1 мин. Раньше было захардкожено 12–19 мин.
    final base = interval.inMinutes;
    final jittered = Duration(
      minutes:
          (base - base ~/ 4 + TransportMimicry.randomInt(base ~/ 2 + 1))
              .clamp(1, 1 << 30),
    );
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(jittered, (_) {
      performSync();
      if (TransportMimicry.instance.enabled) _rejitterTimer();
    });
  }

  /// Starts the foreground service if enabled and not already running.
  Future<void> ensureRunning() async {
    if (!PlatformInfos.isAndroid) return;
    if (!await isEnabled()) return;
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: _serviceChannelId,
          channelName: 'Background sync',
          channelDescription: 'Periodic message check without push services',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(
            interval.inMilliseconds,
          ),
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );
      final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
      await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: AppSettings.applicationName.value,
        notificationText: l10n.backgroundSyncActive,
        callback: galmaxSyncTaskStarter,
      );
      Logs().i('[BackgroundSync] Foreground service started');
    } catch (e, s) {
      Logs().w('[BackgroundSync] Cannot start foreground service', e, s);
    }
  }

  Future<void> stop() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  /// Перезапуск с новым интервалом (после смены настройки).
  Future<void> restart() async {
    await stop();
    _initialized = false;
    await initialize();
    Logs().i('[BackgroundSync] restarted, interval=$interval');
  }

  /// Смена интервала из настроек: сохраняет и перезапускает сервис.
  static Future<void> setIntervalMinutes(int minutes) async {
    final m = minutes.clamp(1, 120);
    await AppSettings.backgroundSyncIntervalMinutes.setItem(m);
    if (await isEnabled()) {
      await BackgroundSyncService().restart();
    }
  }

  void cancel() => stop();

  /// Immediate one-shot sync (settings "Check now" button).
  /// Возвращает отчёт вместо void: раньше любая внутренняя ошибка
  /// глоталась в Logs, а кнопка всегда показывала «OK».
  static Future<BackgroundSyncReport> syncNow() => performSync();

  /// Не-реентерабельность: таймер 15 мин + ручная кнопка + FCM-хендлер
  /// могут вызвать performSync параллельно в одном изоляте. Два писателя
  /// в один sqlite-файл = 'database is locked' / SqliteException(21).
  static bool _running = false;

  static Future<BackgroundSyncReport> performSync() async {
    if (_running) {
      Logs().d('[BackgroundSync] already running, skipping');
      return const BackgroundSyncReport(skipped: true);
    }
    _running = true;
    try {
      // Сериализация с другими изолятами (FCM-фон, тап-фон, сервис):
      // иначе два писателя в один sqlite = 'database is locked'.
      // Лок не взят за 40с — пропускаем, а не висим вечно.
      try {
        return await CrossIsolateMutex.run('matrix_db', _performSyncInner);
      } on TimeoutException {
        Logs().w('[BackgroundSync] db busy in another isolate, skipping');
        return const BackgroundSyncReport(skipped: true);
      }
    } finally {
      _running = false;
    }
  }

  static bool _isTransientSyncError(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString();
    return s.contains('SqliteException(21)') ||
        s.contains('BEGIN IMMEDIATE') ||
        s.contains('bad parameter or other API misuse') ||
        s.contains('database is locked') ||
        s.contains('database table is locked') ||
        s.contains('DatabaseException');
  }

  static Future<void> _oneShotSyncWithRetry(Client client) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
      try {
        // Без таймаута висит до 30 мин (defaultNetworkRequestTimeout):
        // вечный спиннер лечится только убийством процесса.
        await client.oneShotSync().timeout(const Duration(seconds: 60));
        return;
      } catch (e, s) {
        lastError = e;
        lastStack = s;
        if (e is TimeoutException) {
          // Таймаут — не лок, а зависшая сеть: дальше ждать смысла нет.
          Error.throwWithStackTrace(e, s);
        }
        if (!_isTransientSyncError(e) || attempt == 2) {
          Error.throwWithStackTrace(e, s);
        }
        Logs().d(
          '[BackgroundSync] oneShotSync transient lock, retry ${attempt + 1}/3',
          e,
        );
      }
    }
    Error.throwWithStackTrace(
      lastError!,
      lastStack ?? StackTrace.current,
    );
  }

  static Future<BackgroundSyncReport> _performSyncInner() async {
    var clientsChecked = 0;
    var roomsScanned = 0;
    var notified = 0;
    String? firstError;
    try {
      // Крипта нужна для расшифровки событий в фоне (иначе E2EE-чаты молчат).
      try {
        await vod.init();
      } catch (_) {}
      final store = await AppSettings.init();
      final clients = await ClientManager.getClients(
        initialize: false,
        store: store,
      );

      if (clients.isEmpty) {
        return const BackgroundSyncReport(
          error: 'Нет аккаунтов в хранилище',
        );
      }

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('notifications_icon'),
          iOS: DarwinInitializationSettings(),
        ),
      );

      // Канал обязан существовать до show(), иначе на Android 8+ тихо/без звука.
      try {
        final l10nForChannel = await lookupL10n(
          PlatformDispatcher.instance.locale,
        );
        await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              AndroidNotificationChannel(
                AppConfig.pushNotificationsChannelId,
                l10nForChannel.incomingMessages,
                description: 'Notifications for new messages',
                importance: Importance.high,
                enableVibration: true,
                playSound: AppSettings.notificationSoundEnabled.value,
                sound: notificationSound(),
              ),
            );
      } catch (_) {}

      for (final client in clients) {
        if (client.onLoginStateChanged.value != LoginState.loggedIn) continue;

        try {
          // Без init() oneShotSync в фоновом изоляте падает/пустой:
          // клиент создан, но база и ключи не загружены.
          try {
            await client
                .init(
                  waitForFirstSync: false,
                  waitUntilLoadCompletedLoaded: false,
                )
                .timeout(const Duration(seconds: 30));
          } catch (_) {}
          client.backgroundSync = true;
          await _oneShotSyncWithRetry(client);
          clientsChecked++;

          final rooms = client.rooms;
          roomsScanned += rooms.length;
          for (final room in rooms) {
            if (room.isUnreadOrInvited && room.notificationCount > 0) {
              final lastEvent = room.lastEvent;
              if (lastEvent != null && lastEvent.senderId != client.userID) {
                final senderName =
                    lastEvent.senderFromMemoryOrFallback.calcDisplayname();
                final l10n =
                    await lookupL10n(PlatformDispatcher.instance.locale);
                final roomName = room.getLocalizedDisplayname(
                  MatrixLocals(l10n),
                );

                final bodyText = lastEvent.text.length > 100
                    ? '${lastEvent.text.substring(0, 100)}...'
                    : lastEvent.text;

                await plugin.show(
                  id: '${client.clientName}_${room.id}'.hashCode,
                  title: roomName,
                  body: '$senderName: $bodyText',
                  notificationDetails: NotificationDetails(
                    android: AndroidNotificationDetails(
                      AppConfig.pushNotificationsChannelId,
                      l10n.incomingMessages,
                      importance: Importance.high,
                      priority: Priority.high,
                      number: room.notificationCount,
                      groupKey: client.clientName,
                      playSound: AppSettings.notificationSoundEnabled.value,
                      sound: notificationSound(),
                      enableVibration: true,
                    ),
                    iOS: DarwinNotificationDetails(
                      presentAlert: true,
                      presentBadge: true,
                      presentSound:
                          AppSettings.notificationSoundEnabled.value,
                      sound: AppSettings.notificationSoundEnabled.value
                          ? 'notification.caf'
                          : null,
                    ),
                  ),
                  payload: galmaxPushPayload(
                    client.clientName,
                    room.id,
                    lastEvent.eventId,
                  ).toString(),
                );
                notified++;
              }
            }
          }

          // Отложка уходит и с заблокированным телефоном: фон-сервис
          // дёргает performSync по интервалу из настроек.
          try {
            await flushAllScheduled(store, [client]);
          } catch (e, s) {
            Logs().w('[BackgroundSync] Scheduled flush failed', e, s);
          }

          client.backgroundSync = false;
          try {
            await client.dispose(closeDatabase: false);
          } catch (_) {}
        } catch (e, s) {
          try {
            client.backgroundSync = false;
          } catch (_) {}
          firstError ??= e.toString();
          Logs().e(
            '[BackgroundSync] Sync failed for ${client.clientName}',
            e,
            s,
          );
        }
      }
      return BackgroundSyncReport(
        clientsChecked: clientsChecked,
        roomsScanned: roomsScanned,
        notified: notified,
        error: firstError,
      );
    } catch (e, s) {
      Logs().e('[BackgroundSync] Background sync failed', e, s);
      return BackgroundSyncReport(error: e.toString());
    }
  }
}
