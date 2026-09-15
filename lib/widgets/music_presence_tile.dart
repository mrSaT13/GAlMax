// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_media_controller/flutter_media_controller.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/utils/music_presence_service.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/widgets/matrix.dart';

/// Тумблер "Что играет в статус": Android-only, требует доступ к уведомлениям
/// (NotificationListener) и работает пока приложение открыто.
class MusicPresenceTile extends StatefulWidget {
  const MusicPresenceTile({super.key});

  @override
  State<MusicPresenceTile> createState() => _MusicPresenceTileState();
}

class _MusicPresenceTileState extends State<MusicPresenceTile> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _enabled = AppSettings.broadcastMusicPresence.value;
    if (_enabled == true) {
      // Matrix.of нельзя в initState — стартуем после первого кадра.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          MusicPresenceService().ensureStarted(
            clients: Matrix.of(context).clients,
          );
        }
      });
    }
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (value) {
        // Просим доступ к уведомлениям — без него сессий не видно.
        // Откроются системные настройки: найди GAlMax и разреши.
        try {
          await FlutterMediaController.requestPermissions();
        } catch (_) {}
        await AppSettings.broadcastMusicPresence.setItem(true);
        await MusicPresenceService().ensureStarted(
          clients: Matrix.of(context).clients,
        );
      } else {
        await AppSettings.broadcastMusicPresence.setItem(false);
        await MusicPresenceService().stop(
          clients: Matrix.of(context).clients,
        );
      }
      if (mounted) setState(() => _enabled = value);
      if (mounted && value) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Включи трек — статус обновится в течение ~15 сек. Видно тем, с кем есть общая комната.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MusicPresenceService().tick(
        clients: Matrix.of(context).clients,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final svc = MusicPresenceService();
    final seen = svc.lastSeen;
    final err = svc.lastError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err != null
              ? 'Плеер не виден: $err. Дай GAlMax доступ к уведомлениям (Настройки телефона → Уведомления → Доступ к уведомлениям).'
              : seen == null
                  ? 'Опрос ещё не прошёл, подожди ~15 сек и жми снова.'
                  : 'Сейчас вижу: $seen',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformInfos.isAndroid) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final svc = MusicPresenceService();
    final diag = svc.lastCheck == null
        ? null
        : (svc.lastError != null
            ? 'не вижу плеер (ошибка)'
            : svc.lastSeen == null
                ? 'опрос прошёл, тихо'
                : 'вижу: ${svc.lastSeen}');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile.adaptive(
          secondary: Icon(
            Icons.music_note_outlined,
            color: theme.colorScheme.primary,
          ),
          title: const Text(
            'Музыка в статус',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            'Что играет в плеере → 🎵 в статус. Только Android, пока приложение открыто.'
            '${diag == null ? '' : '\nСейчас: $diag'}',
            style: const TextStyle(fontSize: 12),
          ),
          value: _enabled ?? false,
          onChanged: _busy ? null : _toggle,
        ),
        if (_enabled == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _checkNow,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Что я вижу сейчас?'),
              ),
            ),
          ),
      ],
    );
  }
}
