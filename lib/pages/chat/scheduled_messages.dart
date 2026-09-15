// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Отложенная отправка (уровень приложения, без нового нативного кода):
/// сообщение хранится локально и уходит, когда наступит время, а приложение
/// открыто (при открытии чата + таймером, пока чат открыт).
/// Честное ограничение: с убитым приложением Android/iOS не разбудят
/// Flutter-таймер — просроченное уйдёт при следующем открытии чата.
class ScheduledMessage {
  final String id;
  final String text;
  final String? replyEventId;
  final DateTime sendAt;

  ScheduledMessage({
    required this.id,
    required this.text,
    this.replyEventId,
    required this.sendAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (replyEventId != null) 'reply': replyEventId,
    'sendAt': sendAt.millisecondsSinceEpoch,
  };

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) =>
      ScheduledMessage(
        id: json['id'] as String,
        text: json['text'] as String,
        replyEventId: json['reply'] as String?,
        sendAt: DateTime.fromMillisecondsSinceEpoch(json['sendAt'] as int),
      );
}

String _key(String roomId) => 'scheduled_$roomId';

Future<List<ScheduledMessage>> loadScheduled(
  SharedPreferences prefs,
  String roomId,
) async {
  final raw = prefs.getString(_key(roomId));
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(ScheduledMessage.fromJson).toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveScheduled(
  SharedPreferences prefs,
  String roomId,
  List<ScheduledMessage> items,
) {
  return prefs.setString(
    _key(roomId),
    jsonEncode(items.map((e) => e.toJson()).toList()),
  );
}

/// Отправляет всё просроченное. Возвращает количество отправленного.
Future<int> flushDueScheduled(Room room, SharedPreferences prefs) async {
  final items = await loadScheduled(prefs, room.id);
  if (items.isEmpty) return 0;
  final now = DateTime.now();
  var sent = 0;
  final pending = <ScheduledMessage>[];
  for (final item in items) {
    if (!item.sendAt.isAfter(now)) {
      try {
        Event? replyTo;
        if (item.replyEventId != null) {
          // Таймлайн может ещё не содержать событие — тогда без ответа.
          replyTo = null;
        }
        await room.sendTextEvent(item.text, inReplyTo: replyTo);
        sent++;
      } catch (e, s) {
        // Молча не глотаем: иначе «висит отложено» без причин.
        Logs().w(
          '[Scheduled] Send failed in ${room.id}, kept in queue',
          e,
          s,
        );
        pending.add(item);
      }
    } else {
      pending.add(item);
    }
  }
  if (sent > 0) await saveScheduled(prefs, room.id, pending);
  return sent;
}

/// Глобальный флаш по всем комнатам всех клиентов: старт приложения,
/// фоновый синк. Поэтому отложка уходит, даже если чат не открывали,
/// а телефон был заблокирован (в пределах интервала фонового синка).
/// Честное ограничение: Matrix не умеет серверную очередь как Telegram —
/// отправляет клиент, и только пока он жив (foreground + фон-сервис).
Future<int> flushAllScheduled(
  SharedPreferences prefs,
  List<Client> clients,
) async {
  var sent = 0;
  for (final client in clients) {
    if (client.onLoginStateChanged.value != LoginState.loggedIn) continue;
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      try {
        sent += await flushDueScheduled(room, prefs);
      } catch (e, s) {
        Logs().w('[Scheduled] Flush failed for ${room.id}', e, s);
      }
    }
  }
  return sent;
}

/// Диалог планирования: дата + время. Null — отмена.
Future<DateTime?> showScheduleDialog(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (time == null) return null;
  final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!at.isAfter(now)) return null;
  return at;
}

/// Ближайшее запланированное время (для перезапуска таймера).
DateTime? nextScheduledAt(List<ScheduledMessage> items) {
  DateTime? next;
  for (final item in items) {
    if (next == null || item.sendAt.isBefore(next)) next = item.sendAt;
  }
  return next;
}
