// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:flutter/material.dart';

/// Telegram-style frosted glass container: blur behind + translucent tint.
/// Используй для хедеров/панелей поверх скроллящегося контента,
/// чтобы текст не «заезжал» один на другой.
class FrostedGlass extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color? tint;
  final double opacity;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Border? border;

  const FrostedGlass({
    super.key,
    required this.child,
    this.blur = 18,
    this.tint,
    this.opacity = 0.72,
    this.borderRadius,
    this.padding,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveTint = tint ?? colorScheme.surface;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: effectiveTint.withOpacity(opacity),
            borderRadius: borderRadius,
            border:
                border ??
                Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                    width: 0.5,
                  ),
                ),
          ),
          child: child,
        ),
      ),
    );
  }
}
