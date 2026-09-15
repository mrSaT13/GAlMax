// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

/// Маскировка трафика, только клиент (без изменений сервера).
/// Выключатель по умолчанию OFF — поведение остальных не меняется.
///
/// Что делает при ON:
/// - джиттер ретраев sync (поле SDK `syncErrorTimeoutSec` передёргивается
///   таймером в диапазоне уровня — убирает сигнатуру «ровно 3с» при обрывах);
/// - кавер-пинги `GET /versions` со случайным интервалом и мусорным
///   query-параметром случайной длины (размер запроса плавает);
/// - джиттер интервала фонового sync см. `BackgroundSyncService`.
///
/// Честные ограничения:
/// - окно живого long-poll (30с) зашито в SDK — без форка package:matrix
///   его не поменять (кандидат P3 по результатам pcap-теста);
/// - пинги живут только пока жив процесс (как отложенная отправка);
/// - SNI/TLS-фингерпринт Dart-стеком не прячется.
class TransportMimicry with WidgetsBindingObserver {
  static final TransportMimicry instance = TransportMimicry._();
  TransportMimicry._();

  final _random = Random.secure();
  final _clients = <Client>{};
  Timer? _retryJitterTimer;
  Timer? _coverPingTimer;
  bool _observing = false;

  static final _staticRandom = Random.secure();

  /// Случайное 0..max-1 для других модулей (джиттер фонового sync).
  static int randomInt(int max) => _staticRandom.nextInt(max);

  bool get enabled => AppSettings.transportMimicry.value;

  /// 1 = мягко, 2 = агрессивно.
  int get level => AppSettings.mimicryLevel.value.clamp(1, 2);

  /// Подключить клиента (идемпотентно). Вызывать при старте Matrix
  /// и при переключении тумблера.
  void attach(Client client) {
    _clients.add(client);
    if (enabled) {
      _start();
    }
  }

  void detach([Client? client]) {
    if (client == null) {
      _clients.clear();
    } else {
      _clients.remove(client);
    }
    if (_clients.isEmpty) _stop();
  }

  /// Перечитать тумблер (из настроек): вкл — старт, выкл — стоп + откат.
  void refresh() {
    if (enabled && _clients.isNotEmpty) {
      _start();
    } else {
      _stop(restoreDefaults: true);
    }
  }

  void _start() {
    _jitterRetryTimeouts();
    _retryJitterTimer ??= Timer.periodic(
      const Duration(seconds: 45),
      (_) {
        if (!enabled) return;
        _jitterRetryTimeouts();
      },
    );
    _scheduleCoverPing();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  void _stop({bool restoreDefaults = false}) {
    _retryJitterTimer?.cancel();
    _retryJitterTimer = null;
    _coverPingTimer?.cancel();
    _coverPingTimer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    if (restoreDefaults) {
      for (final client in _clients) {
        try {
          client.syncErrorTimeoutSec = 3;
        } catch (_) {}
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // В фоне пинги не шлём — только foreground.
    if (state == AppLifecycleState.resumed && enabled) {
      _scheduleCoverPing();
    } else {
      _coverPingTimer?.cancel();
      _coverPingTimer = null;
    }
  }

  void _jitterRetryTimeouts() {
    // мягко: 3–8с, агрессивно: 5–15с.
    final min = level >= 2 ? 5 : 3;
    final max = level >= 2 ? 15 : 8;
    final value = min + _random.nextInt(max - min + 1);
    for (final client in _clients) {
      try {
        client.syncErrorTimeoutSec = value;
      } catch (_) {}
    }
  }

  void _scheduleCoverPing() {
    _coverPingTimer?.cancel();
    if (!enabled || _clients.isEmpty) return;
    // мягко: 60–120с, агрессивно: 30–90с.
    final min = level >= 2 ? 30 : 60;
    final max = level >= 2 ? 90 : 120;
    final delay = Duration(
      seconds: min + _random.nextInt(max - min + 1),
    );
    _coverPingTimer = Timer(delay, () async {
      await _coverPing();
      if (enabled &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _scheduleCoverPing();
      }
    });
  }

  Future<void> _coverPing() async {
    if (_clients.isEmpty) return;
    // Случайный мусор в query: размер запроса плавает, сервер игнорирует.
    final pad = String.fromCharCodes(
      List.generate(8 + _random.nextInt(25), (_) => 97 + _random.nextInt(26)),
    );
    for (final client in _clients) {
      final homeserver = client.homeserver;
      if (homeserver == null || !client.isLogged()) continue;
      try {
        final uri = homeserver.resolveUri(
          Uri(
            path: '/_matrix/client/versions',
            queryParameters: {'x': pad},
          ),
        );
        await client.httpClient.get(uri).timeout(
          const Duration(seconds: 20),
        );
        // Тело ответа не важно — важен сам факт запроса со случайным таймингом.
      } catch (_) {
        // Кавер-пинг никогда не должен мешать основному flow.
      }
    }
  }
}
