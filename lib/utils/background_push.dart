// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
// Copyright (C) 2020, 2021 Famedly GmbH
// Copyright (C) 2021 galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

//<GOOGLE_SERVICES>import 'package:fcm_shared_isolate/fcm_shared_isolate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/main.dart';
import 'package:galmax/utils/client_manager.dart';
import 'package:galmax/utils/cross_isolate_mutex.dart';
import 'package:galmax/utils/notification_background_handler.dart';
import 'package:galmax/utils/push_helper.dart';
import 'package:galmax/widgets/galmax_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:unifiedpush_ui/unifiedpush_ui.dart';

import '../config/app_config.dart';
import '../config/setting_keys.dart';
import '../widgets/matrix.dart';
import 'platform_infos.dart';

class BackgroundPush {
  static BackgroundPush? _instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<Client> _clients;
  List<Client> get clients => matrix?.widget.clients ?? _clients;

  MatrixState? matrix;
  String? _fcmToken;
  void Function(String errorMsg, {Uri? link})? onFcmError;
  L10n? l10n;

  Future<void> loadLocale() async {
    final context = matrix?.context;
    // inspired by _lookupL10n in .dart_tool/flutter_gen/gen_l10n/l10n.dart
    l10n ??=
        (context != null && context.mounted ? L10n.of(context) : null) ??
        (await L10n.delegate.load(PlatformDispatcher.instance.locale));
  }

  final pendingTests = <String, Completer<void>>{};
  bool firebaseEnabled = false;

  DateTime? lastReceivedPush;

  bool upAction = false;

  Future<void> _init() async {
    // Enable Firebase if available
    try {
      if (Firebase.apps.isNotEmpty) {
        firebaseEnabled = true;
        Logs().v('[Push] Firebase is available');
      }
    } catch (_) {}

    try {
      mainIsolateReceivePort?.listen((message) async {
        try {
          await notificationTap(
            NotificationResponseJson.fromJsonString(message),
            clients: clients,
            router: GAlMaxApp.router,
            l10n: l10n,
          );
        } catch (e, s) {
          Logs().wtf('Main Notification Tap crashed', e, s);
        }
      });
      if (PlatformInfos.isAndroid) {
        final port = ReceivePort();
        IsolateNameServer.removePortNameMapping('background_tab_port');
        IsolateNameServer.registerPortWithName(
          port.sendPort,
          'background_tab_port',
        );
        port.listen((message) async {
          try {
            await notificationTap(
              NotificationResponseJson.fromJsonString(message),
              clients: clients,
              router: GAlMaxApp.router,
              l10n: l10n,
            );
          } catch (e, s) {
            Logs().wtf('Main Notification Tap crashed', e, s);
          }
        });
      }
      await _flutterLocalNotificationsPlugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('notifications_icon'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        ),
        onDidReceiveNotificationResponse: (response) => notificationTap(
          response,
          clients: clients,
          router: GAlMaxApp.router,
          l10n: l10n,
        ),
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
      Logs().v('Flutter Local Notifications initialized');

      // Pre-create notification channels with sounds.
      // ВАЖНО: на Android 8+ звук фиксируется при первом создании канала.
      // Если канал уже был создан без звука (старая установка), звук не
      // появится до переустановки. Поэтому удаляем и создаём заново —
      // так выбранный звук реально применяется.
      if (PlatformInfos.isAndroid) {
        final androidPlugin = _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidPlugin != null) {
          await androidPlugin.deleteNotificationChannel(
            channelId: AppConfig.pushNotificationsChannelId,
          );
          await androidPlugin.deleteNotificationChannel(
            channelId: AppConfig.callNotificationsChannelId,
          );
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              AppConfig.pushNotificationsChannelId,
              'Incoming Messages',
              description: 'Notifications for new messages',
              importance: Importance.high,
              enableVibration: true,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('notification'),
            ),
          );
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              AppConfig.callNotificationsChannelId,
              'Incoming Calls',
              description: 'Notifications for incoming calls',
              importance: Importance.high,
              enableVibration: true,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('call'),
            ),
          );
          Logs().v('Notification channels (re)created with sounds');
        }
      }
      //<GOOGLE_SERVICES>firebase.setListeners(
      //<GOOGLE_SERVICES>  onMessage: (message) => pushHelper(
      //<GOOGLE_SERVICES>    PushNotification.fromJson(
      //<GOOGLE_SERVICES>       message.tryGetMap<String, Object>('data') ?? message,
      //<GOOGLE_SERVICES>    ),
      //<GOOGLE_SERVICES>    clients: clients,
      //<GOOGLE_SERVICES>    l10n: l10n,
      //<GOOGLE_SERVICES>    activeRoomId: matrix?.activeRoomId,
      //<GOOGLE_SERVICES>    flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
      //<GOOGLE_SERVICES>  ),
      //<GOOGLE_SERVICES>);
      if (Platform.isAndroid) {
        await UnifiedPush.initialize(
          onNewEndpoint: _newUpEndpoint,
          onRegistrationFailed: (_, i) => _upUnregistered(i),
          onUnregistered: _upUnregistered,
          onMessage: _onUpMessage,
        );
      }

      // Set up Firebase messaging handlers
      if (firebaseEnabled) {
        // Handle background messages
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          Logs().v('[Push] FCM foreground message received');
          final data = message.data;
          data['devices'] ??= [];
          pushHelper(
            PushNotification.fromJson(data),
            clients: clients,
            l10n: l10n,
            activeRoomId: matrix?.activeRoomId,
            flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
          );
        });

        // Handle notification taps
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          Logs().v('[Push] FCM notification tapped');
          final data = message.data;
          data['devices'] ??= [];
          pushHelper(
            PushNotification.fromJson(data),
            clients: clients,
            l10n: l10n,
            activeRoomId: matrix?.activeRoomId,
            flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
          );
        });

        // Check if app was opened from notification
        final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null) {
          Logs().v('[Push] FCM opened from notification');
          final data = initialMessage.data;
          data['devices'] ??= [];
          pushHelper(
            PushNotification.fromJson(data),
            clients: clients,
            l10n: l10n,
            activeRoomId: matrix?.activeRoomId,
            flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
          );
        }
      }
    } catch (e, s) {
      Logs().e('Unable to initialize Flutter local notifications', e, s);
    }
  }

  BackgroundPush._(this._clients) {
    _init();
  }

  factory BackgroundPush.clientOnly(List<Client> clients) {
    return _instance ??= BackgroundPush._(clients);
  }

  factory BackgroundPush(
    MatrixState matrix, {
    final void Function(String errorMsg, {Uri? link})? onFcmError,
  }) {
    final instance = BackgroundPush.clientOnly(matrix.widget.clients);
    instance.matrix = matrix;
    // ignore: prefer_initializing_formals
    instance.onFcmError = onFcmError;
    return instance;
  }

  /// Makes sure that there is exactly ONE pusher with these settings for this
  /// client and deletes all other pushers if not.
  Future<void> setupPusher({
    required Client client,
    String? gatewayUrl,
    String? token,
    bool useDeviceSpecificAppId = false,
  }) async {
    if (PlatformInfos.isIOS) {
      //<GOOGLE_SERVICES>await firebase.requestPermission();
    }
    if (PlatformInfos.isAndroid && !isIntegrationTest) {
      _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    final appDisplayName = PlatformInfos.appDisplayName;

    final pushers =
        await (client
                .getPushers()
                // Без таймаута висит до 30 мин (defaultNetworkRequestTimeout),
                // если сервер недоступен (напр. дом.сеть 192.168.x.x вне Wi-Fi):
                // кнопка «Починить» молча умирает без снэкбара.
                .timeout(const Duration(seconds: 30))
                .catchError((e) {
          Logs().w('[Push] Unable to request pushers', e);
          return <Pusher>[];
        })) ??
        [];

    // Just the plain app id, we add the .data_message suffix later
    var appId = AppConfig.pushNotificationsAppId;
    // we need the deviceAppId to remove potential legacy UP pusher
    var deviceAppId = '$appId.${client.deviceID}';
    // appId may only be up to 64 chars as per spec
    if (deviceAppId.length > 64) {
      deviceAppId = deviceAppId.substring(0, 64);
    }
    if (!useDeviceSpecificAppId && PlatformInfos.isAndroid) {
      appId += '.data_message';
    }
    final thisAppId = useDeviceSpecificAppId ? deviceAppId : appId;
    if (gatewayUrl == null || token == null) {
      Logs().w('[Push] Missing required push credentials');
      return;
    }

    if (pushers.any(
      (currentPusher) =>
          currentPusher.pushkey == token &&
          currentPusher.data.additionalProperties['client_name'] ==
              client.clientName &&
          currentPusher.kind == 'http' &&
          currentPusher.appId == thisAppId &&
          currentPusher.appDisplayName == appDisplayName &&
          currentPusher.deviceDisplayName == client.deviceName &&
          currentPusher.lang == 'en' &&
          currentPusher.data.url.toString() == gatewayUrl &&
          currentPusher.data.format ==
              AppSettings.pushNotificationsPusherFormat.value &&
          currentPusher.data.additionalProperties['data_message'] ==
              pusherDataMessageFormat,
    )) {
      Logs().i('[Push] Pusher already set for ${client.clientName}');
      return;
    }

    if (!client.isLogged()) return;

    final legacyPushers = pushers.where((pusher) => pusher.pushkey == token);
    for (final pusher in legacyPushers) {
      try {
        await client
            .deletePusher(pusher)
            .timeout(const Duration(seconds: 30));
        Logs().i('[Push] Removed legacy pusher for ${client.clientName}');
      } catch (err) {
        Logs().w(
          '[Push] Failed to remove old pusher for ${client.clientName}',
          err,
        );
      }
    }

    Logs().i('Need to set new pusher for ${client.clientName}');
    try {
      await client
          .postPusher(
        Pusher(
          pushkey: token,
          appId: thisAppId,
          appDisplayName: appDisplayName,
          deviceDisplayName: PlatformInfos.appDisplayName,
          lang: 'en',
          data: PusherData(
            url: Uri.parse(gatewayUrl),
            format: AppSettings.pushNotificationsPusherFormat.value,
            additionalProperties: {
              'client_name': client.clientName,
              'data_message': pusherDataMessageFormat,
            },
          ),
          kind: 'http',
        ),
        append: true,
      )
          .timeout(const Duration(seconds: 30));
    } catch (e, s) {
      Logs().e('[Push] Unable to set pushers', e, s);
    }
  }

  final pusherDataMessageFormat = Platform.isAndroid
      ? 'android'
      : Platform.isIOS
      ? 'ios'
      : null;

  static bool _wentToRoomOnStartup = false;

  Future<void> setupPush() async {
    final context = matrix?.context;
    // FCM — всегда как fallback, даже если есть UP-дистрибьютор.
    // Раньше была ветка if/else: при наличии дистрибьютора setupFirebase
    // вообще не вызывался в этом запуске, а флаг upAction залипал и блочил
    // FCM до рестарта. Итог: сервер шлёт в протухший/пустой канал — тишина,
    // хотя в Element на том же аккаунте всё приходит.
    for (final client in clients) {
      Logs().d('SetupPush for Client ${client.clientName}');
      if (client.onLoginStateChanged.value != LoginState.loggedIn ||
          !PlatformInfos.isMobile ||
          matrix == null) {
        continue;
      }
      await setupFirebase(client);
    }
    if (PlatformInfos.isAndroid &&
        (await UnifiedPush.getDistributors()).isNotEmpty &&
        context != null &&
        context.mounted) {
      try {
        await UnifiedPushUi(
          context: context,
          instances: ['default'],
          unifiedPushFunctions: UPFunctions(),
          showNoDistribDialog: false,
          onNoDistribDialogDismissed: () {}, // TODO: Implement me
        ).registerAppWithDialog();
      } catch (e, s) {
        Logs().w('[Push] UnifiedPush register failed, FCM fallback kept', e, s);
      }
    }

    // ignore: unawaited_futures
    _flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails().then((
      details,
    ) {
      if (details == null ||
          !details.didNotificationLaunchApp ||
          _wentToRoomOnStartup) {
        return;
      }
      _wentToRoomOnStartup = true;
      final response = details.notificationResponse;
      if (response != null) {
        notificationTap(
          response,
          clients: clients,
          router: GAlMaxApp.router,
          l10n: l10n,
        );
      }
    });
  }

  Future<void> _noFcmWarning() async {
    if (matrix == null) {
      return;
    }
    if (AppSettings.showNoGoogle.value) {
      return;
    }
    await loadLocale();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (PlatformInfos.isAndroid) {
        onFcmError?.call(
          l10n!.noGoogleServicesWarning,
          link: Uri.parse(AppConfig.enablePushTutorial),
        );
        return;
      }
      onFcmError?.call(l10n!.oopsPushError);
    });
  }

  Future<void> setupFirebase(Client client) async {
    Logs().v('Setup firebase');
    if (!firebaseEnabled) {
      await _noFcmWarning();
      return;
    }
    if (_fcmToken?.isEmpty ?? true) {
      if (PlatformInfos.isIOS) {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        Logs().v('[Push] iOS permission: ${settings.authorizationStatus}');
      }
      const max = 5;
      for (var i = 0; i < max; i++) {
        try {
          await Future.delayed(const Duration(seconds: 1));
          _fcmToken = await FirebaseMessaging.instance.getToken();
          Logs().v('[Push] FCM token obtained');
          if (_fcmToken != null) break;
        } catch (e, s) {
          Logs().w(
            '[Push] cannot get token - try ($i/$max)',
            e,
            e is String ? null : s,
          );
        }
      }
      if (_fcmToken == null) {
        await _noFcmWarning();
        return;
      }
      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _fcmToken = token;
        Logs().v('[Push] FCM token refreshed');
        for (final client in clients) {
          setupPusher(
            client: client,
            gatewayUrl: AppSettings.pushNotificationsGatewayUrl.value,
            token: token,
          );
        }
      });
    }
    await setupPusher(
      client: client,
      gatewayUrl: AppSettings.pushNotificationsGatewayUrl.value,
      token: _fcmToken,
    );
  }

  Future<void> _newUpEndpoint(PushEndpoint newPushEndpoint, String i) async {
    final newEndpoint = newPushEndpoint.url;
    upAction = true;
    if (newEndpoint.isEmpty) {
      await _upUnregistered(i);
      return;
    }
    var endpoint =
        'https://matrix.gateway.unifiedpush.org/_matrix/push/v1/notify';
    try {
      final url = Uri.parse(newEndpoint)
          .replace(path: '/_matrix/push/v1/notify', query: '')
          .toString()
          .split('?')
          .first;
      final res = json.decode(
        utf8.decode((await http.get(Uri.parse(url))).bodyBytes),
      );
      if (res['gateway'] == 'matrix' ||
          (res['unifiedpush'] is Map &&
              res['unifiedpush']['gateway'] == 'matrix')) {
        endpoint = url;
      }
    } catch (e) {
      Logs().i(
        '[Push] No self-hosted unified push gateway present: $newEndpoint',
      );
    }
    Logs().i('[Push] UnifiedPush using endpoint $endpoint');

    for (final client in clients) {
      await setupPusher(
        client: client,
        gatewayUrl: endpoint,
        token: newEndpoint,
        useDeviceSpecificAppId: true,
      );
    }
    await AppSettings.unifiedPushEndpoint.setItem(newEndpoint);
    await AppSettings.unifiedPushRegistered.setItem(true);
  }

  Future<void> _upUnregistered(String i) async {
    // UP отвалился — снимаем блок с FCM и чиним fallback сразу,
    // иначе upAction=true залипал до рестарта и FCM не пересоздавался.
    upAction = false;
    Logs().i('[Push] Removing UnifiedPush endpoint...');
    await AppSettings.unifiedPushEndpoint.setItem(
      AppSettings.unifiedPushEndpoint.defaultValue,
    );
    await AppSettings.unifiedPushRegistered.setItem(false);
    for (final client in clients) {
      if (client.onLoginStateChanged.value != LoginState.loggedIn) continue;
      try {
        await setupFirebase(client);
      } catch (e, s) {
        Logs().w('[Push] FCM fallback after UP unregister failed', e, s);
      }
    }
  }

  /// Удалить все пушеры и настроить заново: лечит протухшие токены
  /// (FCM token refresh без postPusher) и расщеплённые UP/FCM пары.
  Future<void> repairPushers() async {
    for (final client in clients) {
      if (client.onLoginStateChanged.value != LoginState.loggedIn) continue;
      try {
        final pushers =
            await client.getPushers().timeout(const Duration(seconds: 30)) ??
            [];
        for (final p in pushers) {
          try {
            await client
                .deletePusher(
                  PusherId(appId: p.appId, pushkey: p.pushkey),
                )
                .timeout(const Duration(seconds: 30));
          } catch (e, s) {
            Logs().w('[Push] deletePusher failed ${p.pushkey}', e, s);
          }
        }
      } catch (e, s) {
        Logs().w('[Push] getPushers failed', e, s);
      }
    }
    upAction = false;
    _fcmToken = null;
    // setupPush без таймаута может висеть бесконечно (сеть до homeserver
    // пропала) — кнопка «Починить» тогда молчит без снэкбара. Ограничиваем,
    // чтобы UI всегда ответил успехом или текстом ошибки.
    await setupPush().timeout(const Duration(seconds: 120));
  }

  Future<void> _onUpMessage(PushMessage pushMessage, String i) async {
    Logs().wtf('Push Notification from UP received', pushMessage);
    final message = pushMessage.content;
    upAction = true;
    final data = Map<String, dynamic>.from(
      json.decode(utf8.decode(message))['notification'],
    );
    // UP may strip the devices list
    data['devices'] ??= [];
    await pushHelper(
      PushNotification.fromJson(data),
      clients: clients,
      l10n: l10n,
      activeRoomId: matrix?.activeRoomId,
      flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
      useNotificationActions:
          false, // Buggy with UP: https://codeberg.org/UnifiedPush/flutter-connector/issues/34
    );
  }
}

class UPFunctions extends UnifiedPushFunctions {
  final List<String> features = [
    /*list of features*/
  ];

  @override
  Future<String?> getDistributor() async {
    return await UnifiedPush.getDistributor();
  }

  @override
  Future<List<String>> getDistributors() async {
    return await UnifiedPush.getDistributors(features);
  }

  @override
  Future<void> registerApp(String instance) async {
    await UnifiedPush.register(instance: instance, features: features);
  }

  @override
  Future<void> saveDistributor(String distributor) async {
    await UnifiedPush.saveDistributor(distributor);
  }
}

/// Firebase background message handler — must be top-level
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  Logs().v('[Push] FCM background message received');
  // Ensure Firebase is initialized in background isolate
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Process the push notification like the foreground handler does.
  // Сериализуем с фоновым синком/тапом: два писателя в sqlite = лок.
  // Лок не взят — пропускаем тихо, сообщение доберёт sync при открытии.
  try {
    await CrossIsolateMutex.run('matrix_db', () async {
      await _handleFcmMessage(message);
    });
  } on TimeoutException {
    Logs().w('[Push] FCM background handler skipped, db busy');
  } catch (e, s) {
    Logs().e('[Push] FCM background handler failed', e, s);
  }
}

/// Вынесено из _firebaseMessagingBackgroundHandler ради мьютекса.
Future<void> _handleFcmMessage(RemoteMessage message) async {
  try {
    final data = message.data;
    data['devices'] ??= [];
    final notification = PushNotification.fromJson(data);

    final store = await AppSettings.init();
    try {
      // Нужен для расшифровки E2EE-событий в фоновом изоляте.
      await vod.init();
    } catch (_) {}
    final clients = (await ClientManager.getClients(
      initialize: false,
      store: store,
    ));

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('notifications_icon'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    // Канал должен существовать до show(), иначе на Android 8+ тихо.
    try {
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              AppConfig.pushNotificationsChannelId,
              'Incoming Messages',
              description: 'Notifications for new messages',
              importance: Importance.high,
              enableVibration: true,
              playSound: true,
            ),
          );
    } catch (_) {}

    // Без init() getEventByPushNotification в фоне падает: база не загружена.
    for (final c in clients) {
      try {
        await c
            .init(
              waitForFirstSync: false,
              waitUntilLoadCompletedLoaded: false,
            )
            .timeout(const Duration(seconds: 30));
      } catch (_) {}
    }

    await pushHelper(
      notification,
      clients: clients,
      flutterLocalNotificationsPlugin: plugin,
    );
    for (final c in clients) {
      try {
        await c.dispose(closeDatabase: false);
      } catch (_) {}
    }
  } catch (e, s) {
    Logs().e('[Push] FCM background handler failed', e, s);
  }
}
