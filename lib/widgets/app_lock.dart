// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/widgets/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class AppLockWidget extends StatefulWidget {
  const AppLockWidget({
    required this.child,
    required this.pincode,
    required this.clients,
    super.key,
  });

  final List<Client> clients;
  final String? pincode;
  final Widget child;

  @override
  State<AppLockWidget> createState() => AppLock();
}

class AppLock extends State<AppLockWidget> with WidgetsBindingObserver {
  String? _pincode;
  bool _isLocked = false;
  bool _paused = false;
  bool get isActive => AppLock.isValidPincode(_pincode) && !_paused;

  @override
  void initState() {
    _pincode = widget.pincode;
    _isLocked = isActive;
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_checkLoggedIn);
  }

  Future<void> _checkLoggedIn(_) async {
    if (widget.clients.any((client) => client.isLogged())) return;

    await changePincode(null);
    setState(() {
      _isLocked = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isActive &&
        state == AppLifecycleState.hidden &&
        !_isLocked &&
        isActive) {
      showLockScreen();
    }
  }

  bool get isLocked => _isLocked;

  static bool isValidPincode(String? pincode) =>
      pincode != null &&
      int.tryParse(pincode) != null &&
      pincode.length == 4;

  Future<void> changePincode(String? pincode) async {
    const storage = FlutterSecureStorage();
    // Пустая строка = выключить блокировку: удаляем ключ полностью,
    // иначе '' болтается в хранилище и путает рестарт.
    final normalized = (pincode == null || pincode.isEmpty) ? null : pincode;
    if (normalized == null) {
      await storage.delete(key: 'im.galmax.app_lock');
      await storage.delete(key: 'chat.fluffy.app_lock');
    } else {
      await storage.write(key: 'im.galmax.app_lock', value: normalized);
    }
    if (mounted) {
      setState(() {
        _pincode = normalized;
        // Выключили PIN — сразу разблокировать, включили — заблокировать.
        _isLocked = isValidPincode(normalized);
      });
    } else {
      _pincode = normalized;
      _isLocked = isValidPincode(normalized);
    }
  }

  bool unlock(String pincode) {
    final isCorrect = pincode == _pincode;
    if (isCorrect) {
      setState(() {
        _isLocked = false;
      });
    }
    return isCorrect;
  }

  /// Разблокировка биометрией (отпечаток/лицо) — вместо ввода PIN.
  /// Возвращает true при успехе. PIN остаётся запасным способом.
  /// biometricOnly: false — если биометрия не записана/слабая (лицо без
  /// strong-класса), система предложит код устройства вместо молчаливого
  /// отказа. Раньше с biometricOnly: true на таких девайсах вообще ничего
  /// не подхватывалось.
  Future<bool> unlockWithBiometrics() async {
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      if (!supported) return false;
      final available = await auth.getAvailableBiometrics();
      final ok = await auth.authenticate(
        localizedReason: 'Разблокировать GAlMax',
        options: AuthenticationOptions(
          biometricOnly: available.isNotEmpty,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) {
        setState(() {
          _isLocked = false;
        });
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  bool get biometricEnabled => AppSettings.biometricUnlock.value;

  void showLockScreen() => setState(() {
    _isLocked = true;
  });

  Future<T> pauseWhile<T>(Future<T> future) async {
    _paused = true;
    try {
      return await future;
    } finally {
      _paused = false;
    }
  }

  static AppLock of(BuildContext context) =>
      Provider.of<AppLock>(context, listen: false);

  @override
  Widget build(BuildContext context) => Provider<AppLock>(
    create: (_) => this,
    child: Stack(
      fit: StackFit.expand,
      children: [widget.child, if (isLocked) const LockScreen()],
    ),
  );
}
