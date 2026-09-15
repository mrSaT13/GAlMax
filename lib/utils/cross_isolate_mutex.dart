// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:matrix/matrix.dart';

/// Меж-изолятный мьютекс для тяжёлых обращений к sqlite.
///
/// Проблема: один `*.sqlite`-файл на аккаунт открывают своим коннектом
/// сразу несколько изолятов (UI-синк, таймер фонового синка,
/// foreground-сервис, FCM-фон, тап по уведомлению). `static`-гарды
/// (`BackgroundSyncService._running`, `TimelineMutex`) живут внутри
/// одного изолята и гонку между изолятами не видят — два писателя
/// одновременно дают `SqliteException(21) / 'database is locked'`.
///
/// Решение: lockfile в общем для всех изолятов `systemTemp` (кэш приложения,
/// один на процесс). `File.createSync(exclusive: true)` атомарен: кто создал —
/// тот держит лок. Остальные ждут с короткими слипами (UI не фризится,
/// всё асинхронно) до [acquireTimeout], потом бросают [TimeoutException
/// вместо вечного висения. Протухший лок (держатель умер, файл старше
/// [staleAfter]) сносится ждущим — зависание ограничено сверху.
///
/// Это не покрывает внутренние записи SDK в UI-синк-лупе (туда не влезть
/// без форка SDK), но убирает самый частый кейс: фоновые писатели дерутся
/// друг с другом (таймер + FCM + live-гео + тап). Остаток добивают ретраи
/// по `SQLITE_BUSY` и таймауты на Future.
class CrossIsolateMutex {
  /// Выполнить [action], держа именованный лок [name].
  ///
  /// Бросает [TimeoutException], если лок не удалось взять за
  /// [acquireTimeout] — вызывающий должен пропустить работу (skip),
  /// а не ронять приложение.
  static Future<T> run<T>(
    String name,
    Future<T> Function() action, {
    Duration acquireTimeout = const Duration(seconds: 40),
    Duration staleAfter = const Duration(seconds: 90),
  }) async {
    final lockFile = File('${Directory.systemTemp.path}/galmax_$name.lock');
    final deadline = DateTime.now().add(acquireTimeout);
    var acquired = false;

    while (!acquired) {
      try {
        lockFile.createSync(exclusive: true);
        try {
          lockFile.writeAsStringSync(
            DateTime.now().millisecondsSinceEpoch.toString(),
          );
        } catch (_) {}
        acquired = true;
      } on FileSystemException {
        // Лок занят: проверяем протухание, иначе ждём и ретраим.
        var stale = false;
        try {
          final stamp = int.tryParse(lockFile.readAsStringSync().trim());
          if (stamp != null) {
            final age = DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(stamp),
            );
            if (age > staleAfter) stale = true;
          }
        } catch (_) {
          // Файл пропал между проверками — пробуем заново сразу.
          stale = true;
        }
        if (stale) {
          try {
            lockFile.deleteSync();
          } catch (_) {}
          continue;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException(
            'CrossIsolateMutex($name): lock busy, skipping',
            acquireTimeout,
          );
        }
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    try {
      return await action();
    } finally {
      try {
        lockFile.deleteSync();
      } catch (_) {}
    }
  }
}

/// Проверка «это SQLITE_BUSY-лок, стоит ретраить» — общая для всех мест,
/// чтобы не разъезжались строки-матчеры.
bool isTransientDbLockError(Object e) {
  final s = e.toString();
  return s.contains('database is locked') ||
      s.contains('database table is locked') ||
      s.contains('SqliteException(21)') ||
      s.contains('BEGIN IMMEDIATE') ||
      s.contains('bad parameter or other API misuse') ||
      s.contains('DatabaseException') && s.contains('locked');
}

/// Выполнить [action] с ретраями при transient-локе БД.
/// После [attempts] попыток бросает последнюю ошибку наверх.
Future<T> withDbLockRetry<T>(
  Future<T> Function() action, {
  int attempts = 4,
  String? logTag,
}) async {
  Object? lastError;
  StackTrace? lastStack;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (attempt > 0) {
      await Future.delayed(Duration(milliseconds: 300 * attempt));
    }
    try {
      return await action();
    } catch (e, s) {
      lastError = e;
      lastStack = s;
      if (!isTransientDbLockError(e) || attempt == attempts - 1) {
        Error.throwWithStackTrace(e, s);
      }
      Logs().d(
        '[DB] transient lock, retry ${attempt + 1}/$attempts'
        '${logTag == null ? '' : ' ($logTag)'}',
      );
    }
  }
  Error.throwWithStackTrace(lastError!, lastStack ?? StackTrace.current);
}
