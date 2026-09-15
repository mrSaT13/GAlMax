// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_media_controller/flutter_media_controller.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:matrix/matrix.dart';

/// Трансляция играющего трека в Matrix presence status_msg.
///
/// Android-only: читает активную медиасессию чужого плеера через
/// NotificationListener (плагин flutter_media_controller) и ставит
/// `setPresence(online, statusMsg: "🎵 Artist – Title")`.
/// Работает пока приложение открыто (foreground/background-resumed),
/// опрос раз в 15 сек + только при смене трека (rate-limit Synapse).
///
/// ВАЖНО: сюда передаются ЖИВЫЕ залогиненные клиенты (Matrix.widget.clients).
/// Создавать клиентов через ClientManager здесь нельзя: свежий Client без
/// init() имеет статус loggedOut, список активных пустел — и статус никогда
/// не обновлялся ("опрос ещё не прошёл" навечно). Плюс каждое создание
/// открывало новое соединение к sqlite.
class MusicPresenceService {
  static MusicPresenceService? _instance;
  factory MusicPresenceService() => _instance ??= MusicPresenceService._();
  MusicPresenceService._();

  static const pollInterval = Duration(seconds: 15);
  static const maxStatusLength = 80;

  Timer? _timer;
  String? _lastSent;
  bool _running = false;
  List<Client> _clients = const [];

  bool get isRunning => _running;

  /// Диагностика для UI: что видел последний опрос.
  /// null — опрос ещё не проходил.
  String? lastSeen; // 'Artist – Title' | 'пауза/тихо' | null
  String? lastError; // текст последней ошибки опроса
  DateTime? lastCheck;

  Future<void> ensureStarted({List<Client>? clients}) async {
    if (!PlatformInfos.isAndroid) return;
    if (!AppSettings.broadcastMusicPresence.value) return;
    if (clients != null) _clients = clients;
    if (_running) return;
    _running = true;
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => tick());
    await tick();
    Logs().i('[MusicPresence] started');
  }

  Future<void> stop({bool restore = true, List<Client>? clients}) async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    if (clients != null) _clients = clients;
    if (restore) await _restorePrevious();
    Logs().i('[MusicPresence] stopped');
  }

  static String formatStatus(String? artist, String? track) {
    final a = (artist ?? '').trim();
    final t = (track ?? '').trim();
    final base = a.isEmpty ? t : (t.isEmpty ? a : '$a – $t');
    var s = '🎵 $base'.trim();
    if (s.length > maxStatusLength) {
      s = '${s.substring(0, maxStatusLength - 1)}…';
    }
    return s;
  }

  Future<void> tick({List<Client>? clients}) async {
    try {
      if (!PlatformInfos.isAndroid) return;
      if (!AppSettings.broadcastMusicPresence.value) return;
      if (clients != null) _clients = clients;
      final active = _clients
          .where((c) => c.onLoginStateChanged.value == LoginState.loggedIn)
          .toList();
      if (active.isEmpty) {
        lastCheck = DateTime.now();
        lastError = 'нет активного клиента — открой GalMax и зайди в аккаунт';
        return;
      }

      String? status;
      // Три состояния: играет-с-метаданными / точно тихо / неизвестно
      // (ошибка опроса = нет доступа к уведомлениям или плеер без сессии).
      // Неизвестное НЕ сбрасывает статус в ручной: иначе сторонний плеер
      // с пустыми метаданными будет бесконечно мигать ручным статусом.
      var definitiveIdle = false;
      try {
        final info = await FlutterMediaController.getCurrentMediaInfo();
        lastCheck = DateTime.now();
        // Dart-обёртка плагина глотает PlatformException и возвращает
        // isPlaying=false с track='Error ...' — показываем это как ошибку,
        // а не как «тихо», иначе проблему не диагностировать.
        if (!info.isPlaying && info.track.startsWith('Error')) {
          lastError = info.track;
          Logs().d('[MusicPresence] plugin error: ${info.track}');
          return;
        }
        if (info.isPlaying) {
          final track = info.track.trim();
          final artist = info.artist.trim();
          if (track.isNotEmpty || artist.isNotEmpty) {
            // Фильтр мусора: системные звуки/неизвестные сессии без названий.
            if (track.toLowerCase() != 'unknown' ||
                artist.toLowerCase() != 'unknown') {
              status = formatStatus(artist, track);
              lastSeen = '$artist – $track';
              lastError = null;
            } else {
              lastSeen = 'плеер играет, но названий не отдаёт';
            }
          } else {
            lastSeen = 'плеер играет, но названий не отдаёт';
          }
        } else {
          definitiveIdle = true;
          lastSeen = 'пауза/тихо';
          lastError = null;
        }
      } catch (e, s) {
        lastCheck = DateTime.now();
        lastError = e.toString();
        Logs().d('[MusicPresence] getCurrentMediaInfo failed', e, s);
        return;
      }

      if (status != null) {
        if (status == _lastSent) return;
        // Запоминаем ручной статус один раз, чтобы вернуть при паузе.
        if (_lastSent == null) {
          try {
            final me = active.first;
            final cur = await me.fetchCurrentPresence(me.userID!);
            final manual = cur.statusMsg ?? '';
            if (!manual.startsWith('🎵 ')) {
              await AppSettings.broadcastMusicPreviousStatus.setItem(manual);
            }
          } catch (_) {}
        }
        _lastSent = status;
        for (final client in active) {
          try {
            await client.setPresence(
              client.userID!,
              PresenceType.online,
              statusMsg: status,
            );
            Logs().i('[MusicPresence] status set: $status');
          } catch (e, s) {
            lastError = e.toString();
            Logs().w('[MusicPresence] setPresence failed', e, s);
          }
        }
      } else if (definitiveIdle) {
        // Точно ничего не играет — вернуть ручной статус один раз.
        if (_lastSent != null) {
          _lastSent = null;
          await _restorePrevious();
        }
      }
      // Иначе (неизвестно / играет без метаданных): держим последний
      // отправленный статус, ручной не возвращаем.
    } catch (e, s) {
      Logs().w('[MusicPresence] tick failed', e, s);
    }
  }

  Future<void> _restorePrevious() async {
    try {
      final prev = AppSettings.broadcastMusicPreviousStatus.value;
      for (final client in _clients) {
        if (client.onLoginStateChanged.value != LoginState.loggedIn) continue;
        try {
          await client.setPresence(
            client.userID!,
            PresenceType.online,
            statusMsg: prev,
          );
        } catch (_) {}
      }
    } catch (_) {}
  }
}
