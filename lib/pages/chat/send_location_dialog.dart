// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/chat/events/map_bubble.dart';
import 'package:galmax/utils/live_location_service.dart';
import 'package:galmax/utils/localized_exception_extension.dart';
import 'package:galmax/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:galmax/widgets/future_loading_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

/// Диалог шаринга гео с двумя режимами:
/// 1. «Точка» — выбор произвольной точки тапом по карте (работает и без GPS,
///    в т.ч. на десктопе). Раньше была только текущая позиция.
/// 2. «Live» — трансляция движения серией m.location каждые ~30с
///    (см. LiveLocationService; beacons MSC3489 не рендерятся в этом форке).
class SendLocationDialog extends StatefulWidget {
  final Room room;

  const SendLocationDialog({required this.room, super.key});

  @override
  SendLocationDialogState createState() => SendLocationDialogState();
}

class SendLocationDialogState extends State<SendLocationDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool disabled = false;
  bool denied = false;
  bool isSending = false;
  Position? position;
  Object? error;
  LatLng? picked;
  Duration liveDuration = const Duration(minutes: 15);
  Timer? _ticker;

  bool get liveActive => LiveLocationService().isActive(widget.room.id);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _ticker = Timer.periodic(
      const Duration(seconds: 5),
      (_) => mounted ? setState(() {}) : null,
    );
    requestLocation();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> requestLocation() async {
    if (!(await Geolocator.isLocationServiceEnabled())) {
      setState(() => disabled = true);
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => denied = true);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => denied = true);
      return;
    }
    try {
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 30),
          ),
        );
      } on TimeoutException {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 30),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        position = pos;
        picked ??= LatLng(pos.latitude, pos.longitude);
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  LatLng? get _sendPoint => picked ??
      (position == null
          ? null
          : LatLng(position!.latitude, position!.longitude));

  Future<void> sendStatic() async {
    final point = _sendPoint;
    if (point == null) return;
    setState(() => isSending = true);
    try {
      final body =
          'https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}#map=16/${point.latitude}/${point.longitude}';
      final uri = position != null
          ? 'geo:${point.latitude},${point.longitude};u=${position!.accuracy}'
          : 'geo:${point.latitude},${point.longitude}';
      await showFutureLoadingDialog(
        context: context,
        future: () => LiveLocationService.sendWithRetry(
          widget.room,
          body,
          uri,
        ),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: false).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
  }

  Future<void> toggleLive() async {
    try {
      if (liveActive) {
        await LiveLocationService().stop(roomId: widget.room.id);
      } else {
        await LiveLocationService().start(
          client: widget.room.client,
          roomId: widget.room.id,
          duration: liveDuration,
        );
        if (mounted) Navigator.of(context, rootNavigator: false).pop();
        return;
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = _sendPoint;
    return AlertDialog.adaptive(
      title: Text(L10n.of(context).shareLocation),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabs,
              labelColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(text: 'Точка', icon: Icon(Icons.pin_drop_outlined, size: 18)),
                Tab(text: 'Live', icon: Icon(Icons.navigation_outlined, size: 18)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildPicker(point),
                  _buildLive(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: Navigator.of(context, rootNavigator: false).pop,
          child: Text(L10n.of(context).cancel),
        ),
        if (_tabs.index == 0 && point != null)
          AdaptiveDialogAction(
            onPressed: isSending ? null : sendStatic,
            child: Text(L10n.of(context).send),
          ),
      ],
    );
  }

  Widget _buildPicker(LatLng? point) {
    if (disabled) return Text(L10n.of(context).locationDisabledNotice);
    if (denied && point == null) {
      // Без GPS всё равно можно выбрать точку вручную (дефолт — Москва).
      point = const LatLng(55.7558, 37.6173);
      picked ??= point;
    }
    if (error != null && point == null) {
      return Text(L10n.of(context).errorObtainingLocation(error.toString()));
    }
    if (point == null) {
      return Row(
        mainAxisSize: .min,
        mainAxisAlignment: .center,
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(width: 12),
          Text(L10n.of(context).obtainingLocation),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 240,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: point,
              initialZoom: 14,
              onTap: (_, latLng) => setState(() => picked = latLng),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                fallbackUrl:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 30,
                    height: 30,
                    child: const Icon(
                      Icons.location_pin,
                      color: Colors.red,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Тап по карте двигает пин. Отправится: ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLive() {
    if (liveActive) {
      final left = LiveLocationService().remaining(widget.room.id);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MapBubble(
            latitude: position?.latitude ?? picked?.latitude ?? 55.7558,
            longitude: position?.longitude ?? picked?.longitude ?? 37.6173,
          ),
          const SizedBox(height: 8),
          Text(
            left == null
                ? 'Трансляция активна'
                : 'Трансляция активна, осталось ~${left.inMinutes + 1} мин. Точки идут каждые ~30с.',
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: toggleLive,
            icon: const Icon(Icons.stop_outlined),
            label: const Text('Остановить'),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Движение транслируется серией точек каждые ~30с. Видно во всех клиентах как обычные гео-сообщения.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final d in const [15, 60, 240])
              ChoiceChip(
                label: Text(d >= 60 ? '${d ~/ 60} ч' : '$d мин'),
                selected: liveDuration.inMinutes == d,
                onSelected: (_) =>
                    setState(() => liveDuration = Duration(minutes: d)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (disabled || denied) ? null : toggleLive,
          icon: const Icon(Icons.play_arrow_outlined),
          label: const Text('Начать трансляцию'),
        ),
        if (disabled || denied)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              L10n.of(context).locationPermissionDeniedNotice,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
