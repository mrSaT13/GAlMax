// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:galmax/utils/cross_isolate_mutex.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:geolocator/geolocator.dart';
import 'package:matrix/matrix.dart';

/// Live-трансляция геопозиции серией обычных m.location (sendLocation).
/// Почему не MSC3489 beacons: свой рендер (`message_content.dart`) и Element
/// показывают m.location везде, а m.beacon_info/m.beacon в этом форке не
/// рендерятся — маяк по спеке был бы невидим в самом GalMax.
/// Формат live-точки: body с префиксом 📍 live, тот же geo_uri.
class LiveLocationService {
  static LiveLocationService? _instance;
  factory LiveLocationService() => _instance ??= LiveLocationService._();
  LiveLocationService._();

  static const updateDistanceFilter = 25; // метров
  static const updateInterval = Duration(seconds: 30);

  final Map<String, _LiveSession> _sessions = {};

  /// Foreground-сервис поднят нами (не звонком/синком) — нам его и гасить.
  bool _fgOurs = false;

  bool isActive(String roomId) =>
      _sessions[roomId]?.timer.isActive ?? false;

  Duration? remaining(String roomId) {
    final s = _sessions[roomId];
    if (s == null) return null;
    final left = s.until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  static bool _isTransientDbError(Object e) {
    final s = e.toString();
    return s.contains('database is locked') ||
        s.contains('database table is locked') ||
        s.contains('SqliteException(21)') ||
        s.contains('BEGIN IMMEDIATE') ||
        s.contains('bad parameter or other API misuse') ||
        s.contains('DatabaseException');
  }

  /// Отправка точки с ретраями: sqlite один на UI + фон-синк, случайный
  /// 'database is locked' без этого убивал трансляцию молча.
  /// БД повышать не надо — там уже WAL + busy_timeout=10с, нужен ретрай.
  static Future<void> sendWithRetry(
    Room room,
    String body,
    String uri,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
      try {
        // Сериализуем с фоновым синком: точка каждые 30с — частый
        // триггер 'database is locked'. Лок не взят — шлём напрямую,
        // ретрай ниже подхватит transient-лок.
        try {
          await CrossIsolateMutex.run(
            'matrix_db',
            () => room.sendLocation(body, uri),
            acquireTimeout: const Duration(seconds: 15),
          );
        } on TimeoutException {
          await room.sendLocation(body, uri);
        }
        return;
      } catch (e) {
        lastError = e;
        if (!_isTransientDbError(e) || attempt == 3) rethrow;
        Logs().d('[LiveLocation] transient db lock, retry ${attempt + 1}/4');
      }
    }
    if (lastError != null) throw lastError;
  }

  Future<void> start({
    required Client client,
    required String roomId,
    required Duration duration,
  }) async {
    // Проверка геолокации ДО старта: раньше первая ошибка всплывала только
    // из фонового push и трансляция умирала молча.
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception(
        'Службы геолокации выключены. Включите GPS и попробуйте снова.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception(
        'Нет разрешения на геолокацию. Разрешите доступ и попробуйте снова.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Доступ к геолокации запрещён навсегда. Разрешите в настройках системы.',
      );
    }
    await stop(roomId: roomId, sendStopNotice: false);
    await _ensureForeground();
    final until = DateTime.now().add(duration);
    var count = 0;
    Future<void> push({bool throwOnError = false}) async {
      try {
        final room = client.getRoomById(roomId);
        if (room == null || DateTime.now().isAfter(until)) {
          await stop(roomId: roomId);
          return;
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
        count++;
        final body =
            '📍 live ($count) https://www.openstreetmap.org/?mlat=${pos.latitude}&mlon=${pos.longitude}#map=16/${pos.latitude}/${pos.longitude}';
        final uri = 'geo:${pos.latitude},${pos.longitude};u=${pos.accuracy}';
        await sendWithRetry(room, body, uri);
      } catch (e, s) {
        Logs().w('[LiveLocation] push failed $roomId', e, s);
        if (throwOnError) rethrow;
      }
    }

    await push(throwOnError: true); // первая точка сразу, ошибка — наверх в диалог
    final timer = Timer.periodic(updateInterval, (_) => push());
    // Автостоп по истечении — со стоп-заметкой в чат.
    Timer(duration, () => stop(roomId: roomId));
    _sessions[roomId] = _LiveSession(
      until: until,
      timer: timer,
      client: client,
    );
    Logs().i('[LiveLocation] started $roomId for $duration');
  }

  Future<void> stop({required String roomId, bool sendStopNotice = true}) async {
    final s = _sessions.remove(roomId);
    s?.timer.cancel();
    if (s != null) {
      Logs().i('[LiveLocation] stopped $roomId');
      if (sendStopNotice) {
        try {
          final room = s.client.getRoomById(roomId);
          await room?.sendTextEvent('📍 Трансляция геопозиции завершена');
        } catch (e, st) {
          Logs().w('[LiveLocation] stop notice failed $roomId', e, st);
        }
      }
    }
    await _maybeStopForeground();
  }

  Future<void> stopAll() async {
    for (final id in _sessions.keys.toList()) {
      await stop(roomId: id, sendStopNotice: false);
    }
  }

  /// Держим процесс в фоне на Android: без foreground-сервиса система
  /// убивает таймер и трансляция умирает при сворачивании.
  /// Чужой сервис (звонок/синк) не трогаем — процесс и так жив.
  Future<void> _ensureForeground() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'galmax_live_location',
          channelName: 'Трансляция геопозиции',
          channelDescription: 'Live-геопозиция отправляется в чат',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
        ),
      );
      await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: 'Трансляция геопозиции',
        notificationText: 'Live-гео отправляется в чат',
      );
      _fgOurs = true;
    } catch (e, s) {
      Logs().w('[LiveLocation] cannot start foreground', e, s);
    }
  }

  Future<void> _maybeStopForeground() async {
    if (!PlatformInfos.isAndroid || !_fgOurs) return;
    if (_sessions.isNotEmpty) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
    _fgOurs = false;
  }
}

class _LiveSession {
  final DateTime until;
  final Timer timer;
  final Client client;
  _LiveSession({required this.until, required this.timer, required this.client});
}
