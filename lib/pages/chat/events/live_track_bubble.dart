// SPDX-FileCopyrightText: 2026 Contributors to GAlMax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:galmax/config/app_config.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/live_location_group.dart';
import 'package:galmax/utils/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

/// Один пузырь вместо спама live-точками: маршрут-полилиния,
/// маркеры старта/финиша, счётчик точек.
class LiveTrackBubble extends StatelessWidget {
  final List<Event> points;
  final BuildContext outerContext;

  const LiveTrackBubble(this.points, {required this.outerContext, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latLngs = <LatLng>[];
    for (final e in points) {
      final p = LiveLocationGroup.parseLatLng(e);
      if (p != null) latLngs.add(p);
    }
    if (latLngs.isEmpty) return const SizedBox.shrink();
    final last = latLngs.last;
    final lastEvent = points.last;
    final geoUri = lastEvent.content.tryGet<String>('geo_uri') ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: BoxConstraints.loose(const Size(400, 320)),
          child: AspectRatio(
            aspectRatio: 1.25,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: last,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      maxZoom: 20,
                      minZoom: 0,
                      urlTemplate:
                          'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                      fallbackUrl:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: AppConfig.appId,
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: latLngs,
                          strokeWidth: 4,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: latLngs.first,
                          width: 26,
                          height: 26,
                          child: Icon(
                            Icons.trip_origin,
                            color: theme.colorScheme.secondary,
                            size: 22,
                          ),
                        ),
                        Marker(
                          point: last,
                          width: 30,
                          height: 30,
                          child: Transform.translate(
                            offset: const Offset(0, -12.5),
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Material(
                  color: Colors.transparent,
                  child: Tooltip(
                    message: L10n.of(context).openInMaps,
                    child: InkWell(
                      onTap: () => UrlLauncher(
                        outerContext,
                        geoUri,
                      ).launchUrl(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                Icons.route_outlined,
                size: 14,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Live-трек • ${latLngs.length} точек',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
