// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/routes.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/config/themes.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/proximity_audio_helper.dart';
import 'package:galmax/widgets/app_lock.dart';
import 'package:galmax/widgets/theme_builder.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/custom_scroll_behaviour.dart';
import 'matrix.dart';

class GAlMaxApp extends StatelessWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final String? pincode;
  final SharedPreferences store;

  const GAlMaxApp({
    super.key,
    this.testWidget,
    required this.clients,
    required this.store,
    this.pincode,
  });

  /// getInitialLink may rereturn the value multiple times if this view is
  /// opened multiple times for example if the user logs out after they logged
  /// in with qr code or magic link.
  static bool gotInitialLink = false;

  // Router must be outside of build method so that hot reload does not reset
  // the current path.
  static final GoRouter router = GoRouter(
    routes: AppRoutes.routes,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // Workaround for content sharings passed to go router:
      if ({
        'content',
        'sharemedia-im.galmax.app',
      }.contains(state.uri.scheme)) {
        Logs().d('Ignore content sharing handling in go router', state.uri);
        return '/';
      }

      // Pass deep links to app:
      if (state.uri.toString().startsWith(AppConfig.deepLinkPrefix)) {
        return '/rooms/newprivatechat#${state.uri}';
      }
      return null;
    },
  );

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      builder: (context, themeMode, primaryColor) => MaterialApp.router(
        key: ValueKey(primaryColor),
        title: AppSettings.applicationName.value,
        themeMode: themeMode,
        theme: GalmaxThemes.buildTheme(context, Brightness.light, primaryColor),
        darkTheme: GalmaxThemes.buildTheme(
          context,
          Brightness.dark,
          primaryColor,
        ),
        scrollBehavior: CustomScrollBehavior(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
        builder: (context, child) => AppLockWidget(
          pincode: pincode,
          clients: clients,
          // Need a navigator above the Matrix widget for
          // displaying dialogs
          child: Matrix(
            clients: clients,
            store: store,
            child: _ProximityOverlay(child: testWidget ?? child ?? const SizedBox()),
          ),
        ),
      ),
    );
  }
}

/// Full-screen black overlay that blocks all touch events when proximity sensor
/// detects phone near ear during voice message playback
class _ProximityOverlay extends StatefulWidget {
  final Widget child;
  const _ProximityOverlay({required this.child});

  @override
  State<_ProximityOverlay> createState() => _ProximityOverlayState();
}

class _ProximityOverlayState extends State<_ProximityOverlay> {
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    ProximityAudioHelper.instance.setOverlayCallbacks(
      onShow: () {
        if (mounted) setState(() => _showOverlay = true);
      },
      onHide: () {
        if (mounted) setState(() => _showOverlay = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showOverlay)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // Block all touches
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black),
            ),
          ),
      ],
    );
  }
}
