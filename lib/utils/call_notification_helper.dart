// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:galmax/config/app_config.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CallNotificationHelper {
  static const String _answerAction = 'call_answer';
  static const String _rejectAction = 'call_reject';

  static Future<void> createCallChannel({
    required FlutterLocalNotificationsPlugin plugin,
  }) async {
    final androidPlugin = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    const channel = AndroidNotificationChannel(
      AppConfig.callNotificationsChannelId,
      'Входящие звонки',
      description: 'Уведомления о входящих звонках',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('call'),
    );

    await androidPlugin.createNotificationChannel(channel);
  }

  static Future<void> showIncomingCallNotification({
    required FlutterLocalNotificationsPlugin plugin,
    required String callId,
    required String callerName,
    required String roomName,
    String? callerAvatarUrl,
    bool isVideoCall = false,
    String? payload,
  }) async {
    await createCallChannel(plugin: plugin);

    final callType = isVideoCall ? 'Video' : 'Voice';

    final androidDetails = AndroidNotificationDetails(
      AppConfig.callNotificationsChannelId,
      'Входящие звонки',
      channelDescription: 'Уведомления о входящих звонках',
      importance: Importance.high,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      sound: const RawResourceAndroidNotificationSound('call'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      actions: [
        const AndroidNotificationAction(
          _answerAction,
          'Принять',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          _rejectAction,
          'Отклонить',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      icon: 'notifications_icon',
      largeIcon: callerAvatarUrl != null
          ? FilePathAndroidBitmap(callerAvatarUrl)
          : null,
      styleInformation: BigTextStyleInformation(
        '$callType call from $callerName',
        contentTitle: 'Incoming $callType Call',
        htmlFormatContentTitle: true,
        summaryText: roomName,
      ),
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await plugin.show(
      id: callId.hashCode,
      title: 'Входящий $callType звонок',
      body: '$callerName звонит...',
      notificationDetails: details,
      payload: payload,
    );
  }

  static Future<void> showMissedCallNotification({
    required FlutterLocalNotificationsPlugin plugin,
    required String callId,
    required String callerName,
    required String roomName,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      AppConfig.callNotificationsChannelId,
      'Входящие звонки',
      channelDescription: 'Уведомления о входящих звонках',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      autoCancel: true,
      icon: 'notifications_icon',
      // Без звука осознанно: звонок уже отзвонил рингтоном, лишний гудок
      // после пропущенного/отменённого только путает.
      playSound: false,
      enableVibration: false,
      styleInformation: BigTextStyleInformation(
        'Missed call from $callerName in $roomName',
        contentTitle: 'Missed Call',
        summaryText: roomName,
      ),
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await plugin.show(
      id: callId.hashCode,
      title: 'Пропущенный звонок',
      body: '$callerName вам звонил',
      notificationDetails: details,
    );
  }

  static Future<void> cancelCallNotification({
    required FlutterLocalNotificationsPlugin plugin,
    required String callId,
  }) async {
    await plugin.cancel(id: callId.hashCode);
  }

  static Future<void> cancelAllCallNotifications({
    required FlutterLocalNotificationsPlugin plugin,
  }) async {
    final pendingNotifications = await plugin.pendingNotificationRequests();
    for (final notification in pendingNotifications) {
      await plugin.cancel(id: notification.id);
    }
  }
}
