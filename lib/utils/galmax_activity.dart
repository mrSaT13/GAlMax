// SPDX-FileCopyrightText: 2026 Contributors to GAlMax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Активность GalMax <-> GalMax поверх Matrix.
///
/// Проблема: стандартный `m.typing` — это только bool, различить
/// «печатает» / «записывает голосовое» / «отправляет фото» нельзя.
/// Поэтому:
/// - всем (включая чужие клиенты) шлём обычный `room.setTyping(true)`
///   как fallback — собеседник хотя бы видит «печатает…»;
/// - между своими приложениями шлём to-device `im.galmax.activity`
///   с `{roomId, action, ts}` — в таймлайн ничего не попадает,
///   работает и в шифрованных комнатах.
///
/// Actions: typing, recording_voice, sending_voice, recording_round,
/// uploading_image, uploading_video, uploading_file, stop.
library;

import 'dart:async';

import 'package:matrix/matrix.dart';

class GalmaxActivity {
  static const String type = 'im.galmax.activity';

  static const String typing = 'typing';
  static const String recordingVoice = 'recording_voice';
  static const String sendingVoice = 'sending_voice';
  static const String recordingRound = 'recording_round';
  static const String uploadingImage = 'uploading_image';
  static const String uploadingVideo = 'uploading_video';
  static const String uploadingFile = 'uploading_file';
  static const String stop = 'stop';

  static const Duration throttle = Duration(seconds: 4);
  static const Duration expiry = Duration(seconds: 20);

  static final Map<String, DateTime> _lastSent = {};

  static String actionForMime(String? mime) {
    if (mime == null) return uploadingFile;
    if (mime.startsWith('image')) return uploadingImage;
    if (mime.startsWith('video')) return uploadingVideo;
    if (mime.startsWith('audio')) return sendingVoice;
    return uploadingFile;
  }

  static String labelFor(String action) {
    return switch (action) {
      recordingVoice => 'записывает голосовое…',
      sendingVoice => 'отправляет голосовое…',
      recordingRound => 'записывает видеокружок…',
      uploadingImage => 'отправляет фото…',
      uploadingVideo => 'отправляет видео…',
      uploadingFile => 'отправляет файл…',
      _ => 'печатает…',
    };
  }

  static void send(Room room, String action) {
    final key = '${room.id}/$action';
    final now = DateTime.now();
    if (now.difference(_lastSent[key] ?? DateTime(0)) < throttle) return;
    _lastSent[key] = now;
    // Fallback для чужих клиентов: обычная «печать».
    unawaited(room.setTyping(true, timeout: 15000));
    try {
      final ownId = room.client.userID;
      final userIds = room
          .getParticipants()
          .map((u) => u.id)
          .where((id) => id != ownId)
          .toSet();
      if (userIds.isEmpty) return;
      unawaited(
        room.client.sendToDevicesOfUserIds(
          userIds,
          type,
          {'roomId': room.id, 'action': action, 'ts': now.millisecondsSinceEpoch},
        ),
      );
    } catch (_) {}
  }

  static void stopActivity(Room room) {
    _lastSent.removeWhere((k, _) => k.startsWith('${room.id}/'));
    unawaited(room.setTyping(false));
    try {
      final ownId = room.client.userID;
      final userIds = room
          .getParticipants()
          .map((u) => u.id)
          .where((id) => id != ownId)
          .toSet();
      if (userIds.isEmpty) return;
      unawaited(
        room.client.sendToDevicesOfUserIds(
          userIds,
          type,
          {
            'roomId': room.id,
            'action': stop,
            'ts': DateTime.now().millisecondsSinceEpoch,
          },
        ),
      );
    } catch (_) {}
  }
}

class _ActivityEntry {
  final String userId;
  final String action;
  final DateTime ts;
  const _ActivityEntry(this.userId, this.action, this.ts);
}

/// Приёмник to-device активностей для одного клиента.
class GalmaxActivityStore {
  final Client client;
  final Map<String, Map<String, _ActivityEntry>> _byRoom = {};
  final StreamController<void> _changed = StreamController.broadcast();
  Stream<void> get changed => _changed.stream;

  static final Map<String, GalmaxActivityStore> _instances = {};
  static final Set<String> _watching = {};

  GalmaxActivityStore._(this.client);

  factory GalmaxActivityStore.of(Client client) {
    final key = client.clientName;
    return _instances.putIfAbsent(key, () => GalmaxActivityStore._(client));
  }

  static void watch(Client client) {
    if (!_watching.add(client.clientName)) return;
    final store = GalmaxActivityStore.of(client);
    client.onToDeviceEvent.stream.listen((ev) {
      if (ev.type != GalmaxActivity.type) return;
      final content = ev.content;
      final roomId = content['roomId'];
      final action = content['action'];
      if (roomId is! String || action is! String) return;
      if (ev.senderId == client.userID) return;
      if (action == GalmaxActivity.stop) {
        store._byRoom[roomId]?.remove(ev.senderId);
      } else {
        store._byRoom[roomId] ??= {};
        store._byRoom[roomId]![ev.senderId] = _ActivityEntry(
          ev.senderId,
          action,
          DateTime.now(),
        );
      }
      if (!store._changed.isClosed) store._changed.add(null);
    });
    Timer.periodic(const Duration(seconds: 5), (_) {
      final cutoff = DateTime.now().subtract(GalmaxActivity.expiry);
      var touched = false;
      for (final room in store._byRoom.values) {
        room.removeWhere((_, e) => e.ts.isBefore(cutoff));
        touched = true;
      }
      if (touched && !store._changed.isClosed) store._changed.add(null);
    });
  }

  /// Активности других пользователей в комнате (без протухших).
  Map<String, String> activitiesIn(String roomId) {
    final cutoff = DateTime.now().subtract(GalmaxActivity.expiry);
    final room = _byRoom[roomId];
    if (room == null) return const {};
    room.removeWhere((_, e) => e.ts.isBefore(cutoff));
    return {for (final e in room.entries) e.key: e.value.action};
  }
}
