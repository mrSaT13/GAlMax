// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:galmax/config/setting_keys.dart';

/// Локальный фон приложения (настройка «Фон приложения» в Персонализации).
/// Один виджет для всех экранов: список чатов, профиль, и т.д.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final path = AppSettings.chatLocalBackgroundPath.value;
    if (path.isEmpty) return const SizedBox.shrink();
    final file = File(path);
    if (!file.existsSync()) return const SizedBox.shrink();
    final blur = AppSettings.chatLocalBackgroundBlur.value;
    final opacity = AppSettings.chatLocalBackgroundOpacity.value;
    return Positioned.fill(
      child: Opacity(
        opacity: opacity,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Image.file(file, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
