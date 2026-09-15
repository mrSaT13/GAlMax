// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:galmax/config/setting_keys.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Избранное как в Telegram, с тумблером хранения:
/// - 'server': комната-чат с собой на сервере (синхронизируется между
///   устройствами, переживает переустановку). Комната незашифрована
///   осознанно: иначе пересылка шифрованных медиа ломалась бы о чужие
///   меголм-ключи; шифротекст всё равно только на своём сервере.
/// - 'local': записи только на этом устройстве (SharedPreferences),
///   работают без сети, но не переедут на новый телефон.
class FavoritesHelper {
  static const modeServer = 'server';
  static const modeLocal = 'local';

  static const selfRoomName = 'Избранное';

  /// Старое имя (с эмодзи) — только для поиска уже созданных комнат.
  static const _legacySelfRoomName = '⭐ Избранное';
  static const selfRoomTopic =
      'Личные заметки. Комната только для вас. Не зашифрована — видно администратору сервера.';

  static String get mode => AppSettings.favoritesMode.value;
  static Future<void> setMode(String mode) =>
      AppSettings.favoritesMode.setItem(mode);

  static String _storeKey(String clientName) =>
      'im.galmax.favorites.$clientName';

  /// True, если комната — это «Избранное» (комната с собой).
  /// Используется списком чатов, чтобы скрыть комнату-дубль:
  /// вход в Избранное один — закреплённая плитка над списком.
  static bool isSelfRoom(Room room) {
    final ownId = room.client.userID;
    if (ownId == null) return false;
    if (room.membership != Membership.join) return false;
    if (room.isDirectChat && room.directChatMatrixID == ownId) {
      return true;
    }
    // Fallback: наша комната по имени-топику (если direct-метка слетела).
    if ((room.name == selfRoomName || room.name == _legacySelfRoomName) &&
        room.topic == selfRoomTopic) {
      return true;
    }
    return false;
  }

  /// Комната с собой: прямой чат с собственным userID.
  static Room? findSelfRoom(Client client) {
    final ownId = client.userID;
    if (ownId == null) return null;
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if (room.isDirectChat && room.directChatMatrixID == ownId) {
        return room;
      }
    }
    // Fallback: наша комната по имени-топику (если direct-метка слетела).
    // Принимаем и старое имя с эмодзи '⭐ Избранное' (комнаты, созданные
    // до замены эмодзи на иконку в плитке).
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if ((room.name == selfRoomName ||
              room.name == _legacySelfRoomName) &&
          room.topic == selfRoomTopic) {
        return room;
      }
    }
    return null;
  }

  /// Найти или создать комнату с собой. Возвращает roomId.
  static Future<String> ensureSelfRoom(Client client) async {
    final existing = findSelfRoom(client);
    if (existing != null) return existing.id;
    final roomId = await client
        .createRoom(
          name: selfRoomName,
          topic: selfRoomTopic,
          preset: CreateRoomPreset.trustedPrivateChat,
          isDirect: true,
        )
        .timeout(const Duration(seconds: 30));
    try {
      await Room(id: roomId, client: client).addToDirectChat(client.userID!);
    } catch (e, s) {
      Logs().w('[Favorites] addToDirectChat failed $roomId', e, s);
    }
    try {
      await client.waitForRoomInSync(roomId, join: true).timeout(
        const Duration(seconds: 30),
      );
    } catch (_) {}
    return roomId;
  }

  /// Сохранить событие в избранное по текущему режиму.
  /// Возвращает текст для снекбара.
  static Future<String> saveEvent(Client client, Event event) async {
    if (mode == modeLocal) {
      await _saveLocal(client, event);
      return 'Сохранено в Избранное (только на этом устройстве)';
    }
    final roomId = await ensureSelfRoom(client);
    final room = client.getRoomById(roomId);
    if (room == null) {
      throw Exception('Нет комнаты Избранного');
    }
    final content = Map<String, Object?>.from(event.content);
    if (event.messageType == MessageTypes.Text ||
        event.messageType == MessageTypes.Notice ||
        event.messageType == MessageTypes.Emote) {
      await room.sendTextEvent(event.text);
    } else {
      // Медиа копируется ссылкой на mxc (как переслать): в незашифрованных
      // комнатах откроется, шифрованные вложения из чужих комнат могут
      // не расшифроваться — ограничение v1.
      await room.sendEvent(content, type: event.type);
    }
    // Помечаем, чтобы в списке было видно что это Избранное.
    try {
      await room.addTag('m.favourite');
    } catch (_) {}
    return 'Сохранено в Избранное (синхронизируется)';
  }

  static Future<void> _saveLocal(Client client, Event event) async {
    final store = await SharedPreferences.getInstance();
    final items = await getLocalFavorites(client);
    items.insert(
      0,
      FavoriteItem(
        id: '${event.eventId}_${DateTime.now().millisecondsSinceEpoch}',
        body: event.text,
        senderName: event.senderFromMemoryOrFallback.calcDisplayname(),
        roomName: event.room.getLocalizedDisplayname(),
        ts: DateTime.now().millisecondsSinceEpoch,
        msgtype: event.messageType,
        url: event.content.tryGet<String>('url'),
        mimetype: event.content
            .tryGetMap<String, Object?>('info')
            ?.tryGet<String>('mimetype'),
      ),
    );
    // Храним последние 500, чтобы не раздувать prefs.
    final trimmed = items.take(500).toList();
    await store.setStringList(
      _storeKey(client.clientName),
      trimmed.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  static Future<List<FavoriteItem>> getLocalFavorites(Client client) async {
    final store = await SharedPreferences.getInstance();
    final raw = store.getStringList(_storeKey(client.clientName)) ?? [];
    final items = <FavoriteItem>[];
    for (final s in raw) {
      try {
        items.add(FavoriteItem.fromJson(jsonDecode(s)));
      } catch (_) {}
    }
    return items;
  }

  static Future<void> removeLocalFavorite(Client client, String id) async {
    final store = await SharedPreferences.getInstance();
    final items = await getLocalFavorites(client);
    items.removeWhere((e) => e.id == id);
    await store.setStringList(
      _storeKey(client.clientName),
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  static Future<int> localCount(Client client) async =>
      (await getLocalFavorites(client)).length;
}

class FavoriteItem {
  final String id;
  final String body;
  final String senderName;
  final String roomName;
  final int ts;
  final String msgtype;
  final String? url;
  final String? mimetype;

  const FavoriteItem({
    required this.id,
    required this.body,
    required this.senderName,
    required this.roomName,
    required this.ts,
    required this.msgtype,
    this.url,
    this.mimetype,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'body': body,
    'senderName': senderName,
    'roomName': roomName,
    'ts': ts,
    'msgtype': msgtype,
    if (url != null) 'url': url,
    if (mimetype != null) 'mimetype': mimetype,
  };

  factory FavoriteItem.fromJson(Map<String, Object?> json) => FavoriteItem(
    id: json['id'] as String? ?? '',
    body: json['body'] as String? ?? '',
    senderName: json['senderName'] as String? ?? '',
    roomName: json['roomName'] as String? ?? '',
    ts: (json['ts'] as num?)?.toInt() ?? 0,
    msgtype: json['msgtype'] as String? ?? 'm.text',
    url: json['url'] as String?,
    mimetype: json['mimetype'] as String?,
  );
}
