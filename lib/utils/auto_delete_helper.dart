// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Helper for auto-deleting messages in a room.
/// Сервер удаляет сам по state-событию retention. Стабильный тип —
/// `m.room.retention` (его понимает Synapse); MSC-префикс оставлен как
/// fallback для чтения старых комнат.
///
/// Честно: без поддержки retention на сервере ничего удаляться не будет —
/// клиентский cleanupOldMessages это заглушка (чужие сообщения клиент
/// тереть не вправе, свои — гонка со спамом).
class AutoDeleteHelper {
  /// Подписи в UI на русском (ключи используются только для отображения).
  static const Map<String, int> retentionOptions = {
    'Выкл': 0,
    '1 час': 3600000,
    '8 часов': 28800000,
    '1 день': 86400000,
    '3 дня': 259200000,
    '7 дней': 604800000,
    '30 дней': 2592000000,
  };

  static const _stableType = 'm.room.retention';
  static const _legacyType = 'org.matrix.msc2367.retention';

  /// Get current retention for a room
  static Duration? getCurrentRetention(Room room) {
    try {
      final state =
          room.getState(_stableType) ?? room.getState(_legacyType);
      if (state == null) return null;
      final maxAge = state.content['max_age'] as int?;
      if (maxAge == null || maxAge == 0) return null;
      return Duration(milliseconds: maxAge);
    } catch (_) {
      return null;
    }
  }

  /// Set retention for a room. Бросает MatrixException (напр. M_FORBIDDEN
  /// без прав на state) — caller показывает текст через toLocalizedString.
  static Future<void> setRetention(Room room, Duration duration) async {
    await room.client.setRoomStateWithKey(
      room.id,
      _stableType,
      '',
      {
        'max_age': duration.inMilliseconds,
      },
    );
  }

  /// Remove retention (turn off auto-delete)
  static Future<void> removeRetention(Room room) async {
    await room.client.setRoomStateWithKey(
      room.id,
      _stableType,
      '',
      {
        'max_age': 0,
      },
    );
  }

  /// Clean up old messages in a room (client-side)
  /// Note: This requires server-side support for full auto-delete
  /// Currently just sets the retention policy
  static Future<int> cleanupOldMessages(Room room, {Duration? retention}) async {
    // Server-side cleanup is needed for full auto-delete
    // Client-side redaction only works for our own messages
    return 0;
  }
}
