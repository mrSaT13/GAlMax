// SPDX-FileCopyrightText: 2026 Contributors to GAlMax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Склейка серии live-точек (`📍 live` m.location) в один трек.
///
/// Live-трансляция шлёт обычные m.location каждые ~30с — без склейки они
/// спамят ленту отдельными пузырями. При включённой настройке
/// `AppSettings.groupLiveLocations` серия одного отправителя (разрыв
/// больше 15 мин — новая серия) рисуется одним `LiveTrackBubble` на самой
/// свежей точке, остальные пузыри схлопываются.
library;

import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

class LiveLocationGroup {
  static const String livePrefix = '📍 live';

  /// Разрыв между соседними точками, после которого начинается новая серия.
  static const Duration maxGap = Duration(minutes: 15);

  static bool isLivePoint(Event event) {
    if (event.messageType != MessageTypes.Location) return false;
    if (event.redacted) return false;
    return event.body.startsWith(livePrefix);
  }

  static LatLng? parseLatLng(Event event) {
    final geoUri = Uri.tryParse(event.content.tryGet<String>('geo_uri') ?? '');
    if (geoUri == null || geoUri.scheme != 'geo') return null;
    final parts = geoUri.path.split(';').first.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// Серия для [event] (по возрастанию времени). Пусто — не live-точка.
  static List<Event> groupFor(Event event, Timeline timeline) {
    if (!isLivePoint(event)) return const [];
    final mine = timeline.events
        .where(isLivePoint)
        .where((e) => e.senderId == event.senderId)
        .toList()
      ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    if (mine.isEmpty) return const [];
    // Разбиваем на серии по разрывам, возвращаем серию нашего события.
    var start = 0;
    for (var i = 1; i < mine.length; i++) {
      final gap = mine[i].originServerTs.difference(
        mine[i - 1].originServerTs,
      );
      if (gap > maxGap) {
        if (mine.sublist(start, i).contains(event)) {
          return mine.sublist(start, i);
        }
        start = i;
      }
    }
    return mine.sublist(start);
  }

  /// true — этот пузырь рисует трек (самая свежая точка серии).
  static bool isGroupHead(Event event, Timeline timeline) {
    final group = groupFor(event, timeline);
    if (group.isEmpty) return false;
    return group.last.eventId == event.eventId;
  }
}
