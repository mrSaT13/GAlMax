// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/utils/localized_exception_extension.dart';
import 'package:galmax/utils/transport_mimicry.dart';
import 'package:galmax/widgets/matrix.dart';

/// Тест соединения с сервером при включённой маскировке.
/// Все шаги идут через активные настройки (тот же httpClient клиента).
Future<void> showTransportTestDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _TransportTestDialog(),
  );
}

class _TestStep {
  final String title;
  String? detail;
  bool? ok;
  int? ms;
  _TestStep(this.title);
}

class _TransportTestDialog extends StatefulWidget {
  const _TransportTestDialog();

  @override
  State<_TransportTestDialog> createState() => _TransportTestDialogState();
}

class _TransportTestDialogState extends State<_TransportTestDialog> {
  final _steps = [
    _TestStep('Well-known'),
    _TestStep('Версии сервера'),
    _TestStep('Check homeserver'),
    _TestStep('One-shot sync'),
  ];
  bool _running = true;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final mimicryOn = TransportMimicry.instance.enabled;
    final log = StringBuffer()
      ..writeln('Маскировка: ${mimicryOn ? 'ON' : 'OFF'} '
          '(уровень ${AppSettings.mimicryLevel.value})');

    try {
      // 1. Well-known.
      var sw = Stopwatch()..start();
      final wellKnown = await client.getWellknown().timeout(
        const Duration(seconds: 20),
      );
      sw.stop();
      final baseUrl = wellKnown.mHomeserver.baseUrl;
      _update(0, true, '$baseUrl', sw.elapsedMilliseconds);
      log.writeln('well-known: $baseUrl (${sw.elapsedMilliseconds}ms)');

      final homeserver = baseUrl;

      // 2. /versions напрямую тем же httpClient.
      sw = Stopwatch()..start();
      final versionsUri = homeserver.resolveUri(
        Uri(path: '/_matrix/client/versions'),
      );
      final versionsResp = await client.httpClient
          .get(versionsUri)
          .timeout(const Duration(seconds: 20));
      sw.stop();
      final versionsBody = versionsResp.body;
      final versionsOk = versionsResp.statusCode == 200;
      _update(
        1,
        versionsOk,
        versionsOk
            ? (versionsBody.length > 80
                  ? '${versionsBody.substring(0, 80)}…'
                  : versionsBody)
            : 'HTTP ${versionsResp.statusCode}',
        sw.elapsedMilliseconds,
      );
      log.writeln('versions: HTTP ${versionsResp.statusCode} '
          '(${sw.elapsedMilliseconds}ms)');

      // 3. Check homeserver (тот же flow, что в логине).
      sw = Stopwatch()..start();
      final check = await client
          .checkHomeserver(homeserver)
          .timeout(const Duration(seconds: 30));
      sw.stop();
      // checkHomeserver возвращает record (wellKnown, versions, flows, auth).
      final flows = check.$3.length;
      _update(2, true, 'login flows: $flows', sw.elapsedMilliseconds);
      log.writeln('checkHomeserver: flows=$flows '
          '(${sw.elapsedMilliseconds}ms)');

      // 4. Один sync проход с замером.
      sw = Stopwatch()..start();
      await client
          .oneShotSync()
          .timeout(const Duration(seconds: 60));
      sw.stop();
      _update(3, true, 'sync проход завершён', sw.elapsedMilliseconds);
      log.writeln('oneShotSync: ok (${sw.elapsedMilliseconds}ms)');
    } catch (e) {
      if (!mounted) return;
      final message = e is Exception
          ? e.toLocalizedString(context)
          : e.toString();
      log.writeln('ОШИБКА: $message');
      if (mounted) {
        setState(() {
          _fatal = message;
          _running = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _running = false);
    }
  }

  void _update(int i, bool ok, String detail, int ms) {
    if (!mounted) return;
    setState(() {
      _steps[i]
        ..ok = ok
        ..detail = detail
        ..ms = ms;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allOk =
        !_running && _fatal == null && _steps.every((s) => s.ok == true);
    return AlertDialog(
      title: const Text('Проверка соединения'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _steps.length; i++)
                _stepTile(_steps[i], _running && _isCurrent(i)),
              if (_fatal != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _fatal!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (!_running)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    allOk
                        ? 'Соединение в порядке — маскировка не мешает sync.'
                        : 'Есть ошибки — смотри шаги выше.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_running)
          TextButton.icon(
            onPressed: () {
              final buf = StringBuffer();
              for (final s in _steps) {
                buf.writeln(
                  '${s.ok == true ? 'OK' : 'FAIL'} ${s.title}: '
                  '${s.detail ?? ''} ${s.ms ?? ''}ms',
                );
              }
              if (_fatal != null) buf.writeln('ОШИБКА: $_fatal');
              Clipboard.setData(ClipboardData(text: buf.toString()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Результат скопирован')),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Копировать'),
          ),
        if (!_running)
          TextButton.icon(
            onPressed: () {
              setState(() {
                for (final s in _steps) {
                  s.ok = null;
                  s.detail = null;
                  s.ms = null;
                }
                _fatal = null;
                _running = true;
              });
              _run();
            },
            icon: const Icon(Icons.refresh_outlined, size: 18),
            label: const Text('Ещё раз'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_running ? 'Отмена' : 'Закрыть'),
        ),
      ],
    );
  }

  bool _isCurrent(int i) {
    for (var j = 0; j < _steps.length; j++) {
      if (_steps[j].ok == null) return i == j;
    }
    return false;
  }

  Widget _stepTile(_TestStep step, bool active) {
    final icon = step.ok == null
        ? (active
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Icon(Icons.pending_outlined))
        : step.ok == true
        ? const Icon(Icons.check_circle_outlined, color: Colors.green)
        : const Icon(Icons.error_outlined, color: Colors.red);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: icon,
      title: Text(step.title),
      subtitle: step.detail == null
          ? null
          : Text(
              '${step.detail!}${step.ms != null ? ' · ${step.ms}ms' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
    );
  }
}
