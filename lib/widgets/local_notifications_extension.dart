// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/client_download_content_extension.dart';
import 'package:galmax/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:galmax/utils/notification_background_handler.dart';
import 'package:galmax/utils/push_helper.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/sounds/notification.ogg'
    ..load();

  Future<void> showLocalNotification(Event event) async {
    final l10n = L10n.of(context);
    final roomId = event.room.id;
    if (activeRoomId == roomId) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    final title = event.room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix:
          !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == client.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );
    final avatarUrl = event.room.avatar;

    const size = 128;
    const thumbnailMethod = ThumbnailMethod.crop;

    if (avatarUrl != null) {
      // Pre-cache so that we can later just set the thumbnail uri as icon:
      try {
        await client.downloadMxcCached(
          avatarUrl,
          width: size,
          height: size,
          thumbnailMethod: thumbnailMethod,
          isThumbnail: true,
          rounded: true,
        );
      } catch (e, s) {
        Logs().d('Unable to pre-download avatar for web notification', e, s);
      }
    }

    if (kIsWeb) {
      final thumbnailUri = await avatarUrl?.getThumbnailUri(
        client,
        width: size,
        height: size,
        method: thumbnailMethod,
      );

      if (AppSettings.webNotificationSound.value) _audioPlayer.play();

      html.Notification(
        title,
        body: body,
        icon: thumbnailUri?.toString(),
        tag: event.room.id,
      );
      return;
    }

    FlutterLocalNotificationsPlugin().show(
      id: event.room.id.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          AppConfig.pushNotificationsChannelId,
          l10n.incomingMessages,
          importance: Importance.high,
          priority: Priority.high,
          playSound: AppSettings.notificationSoundEnabled.value,
          sound: notificationSound(),
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: AppSettings.notificationSoundEnabled.value,
          sound: AppSettings.notificationSoundEnabled.value
              ? 'notification.caf'
              : null,
          threadIdentifier: event.room.id,
        ),
        linux: LinuxNotificationDetails(
          sound: ThemeLinuxSound('message-new-instant'),
          actions: [
            LinuxNotificationAction(
              key: galmaxNotificationActions.markAsRead.name,
              label: l10n.markAsRead,
            ),
            LinuxNotificationAction(
              key: galmaxNotificationActions.mute.name,
              label: l10n.mute,
            ),
          ],
        ),
      ),
      payload: galmaxPushPayload(
        client.clientName,
        event.room.id,
        event.eventId,
      ).toString(),
    );
  }
}
