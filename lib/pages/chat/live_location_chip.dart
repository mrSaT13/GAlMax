// SPDX-FileCopyrightText: 2026 Contributors to GAlMax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:galmax/utils/live_location_service.dart';
import 'package:matrix/matrix.dart';

/// Чип под шапкой чата: «Трансляция гео идёт, осталось N мин» + стоп.
class LiveLocationChip extends StatefulWidget {
  final Room room;

  const LiveLocationChip(this.room, {super.key});

  @override
  State<LiveLocationChip> createState() => _LiveLocationChipState();
}

class _LiveLocationChipState extends State<LiveLocationChip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 10),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!LiveLocationService().isActive(widget.room.id)) {
      return const SizedBox.shrink();
    }
    final left = LiveLocationService().remaining(widget.room.id);
    final text = left == null
        ? 'Трансляция геопозиции идёт'
        : 'Трансляция геопозиции • осталось ~${left.inMinutes + 1} мин';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.navigation_outlined,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await LiveLocationService().stop(
                    roomId: widget.room.id,
                  );
                  if (mounted) setState(() {});
                },
                child: const Text('Стоп'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
