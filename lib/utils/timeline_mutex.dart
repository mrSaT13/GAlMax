// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

/// Сериализует тяжёлые обращения к БД (getTimeline), чтобы два параллельных
/// `room.getTimeline()` (открытие чата + экспорт, быстрый переход между
/// чатами) не сталкивались в sqflite FFI транзакциями и не давали
/// `SqliteException(21) ... 'BEGIN IMMEDIATE'`.
///
/// Это не лечит гонки с фоновым изолятом пушей (там своё соединение),
/// но убирает самый частый триггер — два ридера в UI-изоляте.
class TimelineMutex {
  static Future<void> _chain = Future.value();

  static Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }
}
