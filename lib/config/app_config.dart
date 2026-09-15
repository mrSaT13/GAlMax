// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

abstract class AppConfig {
  static const Color primaryColor = Color(0xFF2E7D32);

  static const Color chatColor = primaryColor;
  static const Color accentColor = Color(0xFF4CAF50);
  static const Color darkBackground = Color(0xFF121E12);
  static const Color darkSurface = Color(0xFF1A2A1A);
  static const Color darkCard = Color(0xFF1E2E1E);
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'im.galmax://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'galmax_push';
  static const String callNotificationsChannelId = 'galmax_call';
  static const String pushNotificationsAppId = 'im.galmax.app';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  static const String enablePushTutorial =
      'https://galmax.im/faq/#push_without_google_services';
  static const String encryptionTutorial =
      'https://galmax.im/faq/#how_to_use_end_to_end_encryption';
  static const String startChatTutorial =
      'https://galmax.im/faq/#how_do_i_find_other_users';
  static const String howDoIGetStickersTutorial =
      'https://galmax.im/faq/#how_do_i_get_stickers';
  static const String appId = 'im.galmax.app';
  static const String appOpenUrlScheme = 'im.galmax';
  static const String appSsoUrlScheme = 'im.galmax.auth';

  static const String sourceCodeUrl = 'https://github.com/mrSaT13/GAlMax';
  static const String supportUrl = 'https://github.com/mrSaT13/GAlMax/issues';
  static const String changelogUrl = 'https://galmax.im/changelog/';
  static const String helpUrl =
      'https://galmax.im/faq/#how_can_i_support_galmax';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/mrSaT13/GAlMax/issues/new',
  );

  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'raw.githubusercontent.com',
    path: 'mrSaT13/GAlMax/refs/heads/main/recommended_homeservers.json',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';
}
