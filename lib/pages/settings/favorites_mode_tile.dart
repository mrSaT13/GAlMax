// SPDX-FileCopyrightText: 2026 Contributors to GAlMax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:galmax/utils/favorites_helper.dart';

/// Тумблер Избранного: где хранить — комната с собой на сервере
/// (синхронизируется) или только на этом устройстве (локально).
/// Используется и в главных настройках, и в настройках чата.
class FavoritesModeTile extends StatefulWidget {
  const FavoritesModeTile({super.key});

  @override
  State<FavoritesModeTile> createState() => FavoritesModeTileState();
}

class FavoritesModeTileState extends State<FavoritesModeTile> {
  Future<void> _pickMode() async {
    final current = FavoritesHelper.mode;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.star, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            // Flexible: на узких экранах и при крупном шрифте заголовок
            // переносится, а не вылезает за границы диалога.
            Flexible(child: Text('Избранное: где хранить')),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: FavoritesHelper.modeServer,
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              dense: true,
              title: const Text('Комната с собой'),
              subtitle: const Text(
                'Синхронизируется между устройствами, переживёт переустановку',
                style: TextStyle(fontSize: 12),
              ),
            ),
            RadioListTile<String>(
              value: FavoritesHelper.modeLocal,
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              dense: true,
              title: const Text('Только на устройстве'),
              subtitle: const Text(
                'Приватно, работает без сети, не переедет на новый телефон',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (picked != null && picked != current && mounted) {
      await FavoritesHelper.setMode(picked);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocal = FavoritesHelper.mode == FavoritesHelper.modeLocal;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.star_outlined, color: Colors.amber, size: 20),
      ),
      title: const Text(
        'Избранное',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        isLocal ? 'Только на этом устройстве' : 'Комната с собой • синхронизируется',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurface.withOpacity(0.3),
        size: 20,
      ),
      onTap: _pickMode,
    );
  }
}
