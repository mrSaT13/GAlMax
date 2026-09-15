// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/client_manager.dart';
import 'package:galmax/utils/init_with_restore.dart';
import 'package:galmax/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:galmax/utils/music_presence_service.dart';
import 'package:galmax/utils/notification_background_handler.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/utils/transport_mimicry.dart';
import 'package:galmax/utils/uia_request_manager.dart';
import 'package:galmax/utils/voip_plugin.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:galmax/widgets/galmax_app.dart';
import 'package:galmax/widgets/future_loading_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher_string.dart';

import '../config/setting_keys.dart';
import '../pages/key_verification/key_verification_dialog.dart';
import '../utils/account_bundles.dart';
import '../utils/background_push.dart';
import '../utils/galmax_activity.dart';
import 'local_notifications_extension.dart';

class Matrix extends StatefulWidget {
  final Widget? child;

  final List<Client> clients;

  final Map<String, String>? queryParameters;

  final SharedPreferences store;

  const Matrix({
    this.child,
    required this.clients,
    required this.store,
    this.queryParameters,
    super.key,
  });

  @override
  MatrixState createState() => MatrixState();

  /// Returns the (nearest) Client instance of your application.
  static MatrixState of(BuildContext context) =>
      Provider.of<MatrixState>(context, listen: false);
}

class MatrixState extends State<Matrix> with WidgetsBindingObserver {
  int _activeClient = -1;
  String? activeBundle;

  SharedPreferences get store => widget.store;

  XFile? loginAvatar;
  String? loginUsername;
  bool? loginRegistrationSupported;

  BackgroundPush? backgroundPush;

  Client get client {
    if (_activeClient < 0 || _activeClient >= widget.clients.length) {
      return currentBundle!.first!;
    }
    return widget.clients[_activeClient];
  }

  /// Все клиенты (включая неактивные аккаунты) — например для фоновых
  /// сервисов (трансляция музыки в статус), которым нужны живые клиенты.
  List<Client> get clients => widget.clients;

  VoipPlugin? voipPlugin;

  bool get isMultiAccount => widget.clients.length > 1;

  int getClientIndexByMatrixId(String matrixId) =>
      widget.clients.indexWhere((client) => client.userID == matrixId);

  late String currentClientSecret;
  RequestTokenResponse? currentThreepidCreds;

  void setActiveClient(Client? cl) {
    final i = widget.clients.indexWhere((c) => c == cl);
    if (i != -1) {
      _activeClient = i;
      // TODO: Multi-client VoiP support
      createVoipPlugin();
    } else {
      Logs().w('Tried to set an unknown client ${cl!.userID} as active');
    }
  }

  List<Client?>? get currentBundle {
    if (!hasComplexBundles) {
      return List.from(widget.clients);
    }
    final bundles = accountBundles;
    if (bundles.containsKey(activeBundle)) {
      return bundles[activeBundle];
    }
    return bundles.values.first;
  }

  Map<String?, List<Client?>> get accountBundles {
    final resBundles = <String?, List<_AccountBundleWithClient>>{};
    for (var i = 0; i < widget.clients.length; i++) {
      final bundles = widget.clients[i].accountBundles;
      for (final bundle in bundles) {
        if (bundle.name == null) {
          continue;
        }
        resBundles[bundle.name] ??= [];
        resBundles[bundle.name]!.add(
          _AccountBundleWithClient(client: widget.clients[i], bundle: bundle),
        );
      }
    }
    for (final b in resBundles.values) {
      b.sort(
        (a, b) => a.bundle!.priority == null
            ? 1
            : b.bundle!.priority == null
            ? -1
            : a.bundle!.priority!.compareTo(b.bundle!.priority!),
      );
    }
    return resBundles.map(
      (k, v) => MapEntry(k, v.map((vv) => vv.client).toList()),
    );
  }

  bool get hasComplexBundles => accountBundles.values.any((v) => v.length > 1);

  Client? _loginClientCandidate;

  AudioPlayer? audioPlayer;
  final ValueNotifier<String?> voiceMessageEventId = ValueNotifier(null);

  Future<Client> getLoginClient() async {
    if (widget.clients.isNotEmpty && !client.isLogged()) {
      return client;
    }
    final candidate = _loginClientCandidate ??=
        await ClientManager.createClient(
            '${AppSettings.applicationName.value}-${DateTime.now().millisecondsSinceEpoch}',
            store,
          )
          ..onLoginStateChanged.stream
              .where((l) => l == LoginState.loggedIn)
              .first
              .then((_) {
                if (!widget.clients.contains(_loginClientCandidate)) {
                  widget.clients.add(_loginClientCandidate!);
                }
                ClientManager.addClientNameToStore(
                  _loginClientCandidate!.clientName,
                  store,
                );
                _registerSubs(_loginClientCandidate!.clientName);
                setActiveClient(_loginClientCandidate);
                _loginClientCandidate = null;
                GAlMaxApp.router.go('/backup');
              });
    if (widget.clients.isEmpty) widget.clients.add(candidate);
    return candidate;
  }

  Client? getClientByName(String name) =>
      widget.clients.firstWhereOrNull((c) => c.clientName == name);

  final onRoomKeyRequestSub = <String, StreamSubscription>{};
  final onKeyVerificationRequestSub = <String, StreamSubscription>{};
  final onNotification = <String, StreamSubscription>{};
  final onLogoutSub = <String, StreamSubscription<LoginState>>{};
  final onUiaRequest = <String, StreamSubscription<UiaRequest>>{};
  final onSyncStatusSub = <String, StreamSubscription>{};

  /// Счётчик подряд идущих ошибок синка с клином sqlite (по клиентам).
  /// Сбрасывается при первом успешном синке.
  final _dbErrorCounts = <String, int>{};
  bool _dbRecovering = false;
  DateTime? _lastDbRecovery;

  String? _cachedPassword;
  Timer? _cachedPasswordClearTimer;

  String? get cachedPassword => _cachedPassword;

  set cachedPassword(String? p) {
    Logs().d('Password cached');
    _cachedPasswordClearTimer?.cancel();
    _cachedPassword = p;
    _cachedPasswordClearTimer = Timer(const Duration(minutes: 10), () {
      _cachedPassword = null;
      Logs().d('Cached Password cleared');
    });
  }

  String? get activeRoomId {
    final route = GAlMaxApp.router.routeInformationProvider.value.uri.path;
    if (!route.startsWith('/rooms/')) return null;
    return route.split('/')[2];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initMatrix();
  }

  void _registerSubs(String name) {
    final c = getClientByName(name);
    if (c == null) {
      Logs().w(
        'Attempted to register subscriptions for non-existing client $name',
      );
      return;
    }
    onRoomKeyRequestSub[name] ??= c.onRoomKeyRequest.stream.listen((
      RoomKeyRequest request,
    ) async {
      if (widget.clients.any(
        ((cl) =>
            cl.userID == request.requestingDevice.userId &&
            cl.identityKey == request.requestingDevice.curve25519Key),
      )) {
        Logs().i(
          '[Key Request] Request is from one of our own clients, forwarding the key...',
        );
        await request.forwardKey();
      }
    });
    onKeyVerificationRequestSub[name] ??= c.onKeyVerificationRequest.stream
        .listen((KeyVerification request) async {
          var hidPopup = false;
          request.onUpdate = () {
            if (!hidPopup &&
                {
                  KeyVerificationState.done,
                  KeyVerificationState.error,
                }.contains(request.state)) {
              GAlMaxApp.router.pop('dialog');
            }
            hidPopup = true;
          };
          request.onUpdate = null;
          hidPopup = true;
          await KeyVerificationDialog(request: request).show(
            GAlMaxApp.router.routerDelegate.navigatorKey.currentContext ??
                context,
          );
        });
    onLogoutSub[name] ??= c.onLoginStateChanged.stream
        .where((state) => state == LoginState.loggedOut)
        .listen((_) {
          final loggedInWithMultipleClients = widget.clients.length > 1;

          _cancelSubs(c.clientName);
          TransportMimicry.instance.detach(c);
          widget.clients.remove(c);
          ClientManager.removeClientNameFromStore(c.clientName, store);
          InitWithRestoreExtension.deleteSessionBackup(name);

          if (loggedInWithMultipleClients) {
            final snackbarContext =
                GAlMaxApp
                    .router
                    .routerDelegate
                    .navigatorKey
                    .currentContext ??
                context;

            if (!snackbarContext.mounted) return;
            final l10n = L10n.of(snackbarContext);
            ScaffoldMessenger.of(
              snackbarContext,
            ).showSnackBar(SnackBar(content: Text(l10n.oneClientLoggedOut)));
            return;
          }
          GAlMaxApp.router.go('/');
        });
    onUiaRequest[name] ??= c.onUiaRequest.stream.listen(uiaRequestHandler);
    // To-device активности GalMax<->GalMax (запись голосового, аплоад фото).
    GalmaxActivityStore.watch(c);
    onSyncStatusSub[name] ??= c.onSyncStatus.stream.listen((update) {
      _watchSyncDbHealth(c.clientName, update);
    });
    if (PlatformInfos.isWeb || PlatformInfos.isLinux) {
      FlutterLocalNotificationsPlugin().initialize(
        settings: InitializationSettings(
          linux: LinuxInitializationSettings(
            defaultActionName: galmaxNotificationActions.open.name,
          ),
        ),
        onDidReceiveNotificationResponse: (response) => notificationTap(
          response,
          clients: widget.clients,
          router: GAlMaxApp.router,
          l10n: null,
        ),
      );
      c.onSync.stream.first.then((s) {
        html.Notification.requestPermission();
        onNotification[name] ??= c.onNotification.stream.listen(
          showLocalNotification,
        );
      });
    }
  }

  void _cancelSubs(String name) {
    onRoomKeyRequestSub[name]?.cancel();
    onRoomKeyRequestSub.remove(name);
    onKeyVerificationRequestSub[name]?.cancel();
    onKeyVerificationRequestSub.remove(name);
    onLogoutSub[name]?.cancel();
    onLogoutSub.remove(name);
    onNotification[name]?.cancel();
    onNotification.remove(name);
    onSyncStatusSub[name]?.cancel();
    onSyncStatusSub.remove(name);
  }

  /// Сторож клина sqlite: цикл синка в SDK неубиваем (перезапускается в
  /// `whenComplete`), поэтому заклинивший коннект (`SqliteException(21)`
  /// на каждом синке, события не читаются/не расшифровываются, инвайты
  /// звонков не обрабатываются) висит вечно до убийства процесса.
  /// После 5 подряд sqlite-ошибок пересоздаём клиент (свежий коннект к
  /// тому же файлу, сессия не теряется) — программный force-stop.
  static const _dbErrorThreshold = 5;

  static bool _isWedgedDbError(Object? e) {
    if (e == null) return false;
    final s = e.toString();
    return s.contains('SqliteException') ||
        s.contains('DatabaseException') ||
        s.contains('sqlite_error') ||
        s.contains('database is locked') ||
        s.contains('BEGIN IMMEDIATE') ||
        s.contains('bad parameter or other API misuse') ||
        s.contains('MISUSE');
  }

  void _watchSyncDbHealth(String name, SyncStatusUpdate update) {
    if (update.status == SyncStatus.finished) {
      _dbErrorCounts.remove(name);
      return;
    }
    if (update.status != SyncStatus.error) return;
    if (!_isWedgedDbError(update.error?.exception)) {
      // Не sqlite (сеть и т.п.) — счётчик клина не трогаем.
      return;
    }
    final n = (_dbErrorCounts[name] ?? 0) + 1;
    _dbErrorCounts[name] = n;
    Logs().w('[DB] Consecutive sync sqlite errors for $name: $n');
    if (n >= _dbErrorThreshold) {
      _dbErrorCounts.remove(name);
      final c = getClientByName(name);
      if (c != null) {
        // ignore: unawaited_futures
        _recoverWedgedDatabase(c);
      }
    }
  }

  Future<void> _recoverWedgedDatabase(Client old) async {
    if (_dbRecovering) return;
    final last = _lastDbRecovery;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      Logs().w('[DB] Recovery on cooldown, skipping');
      return;
    }
    _dbRecovering = true;
    try {
      Logs().w(
        '[DB] Sync wedged on sqlite errors, rebuilding connection for ${old.clientName}',
      );
      _showDbRecoverySnack(
        'База подвисла — переподключаю, это займёт несколько секунд…',
      );
      final name = old.clientName;
      final wasActive = widget.clients.contains(old) && client == old;
      try {
        await old.abortSync().timeout(const Duration(seconds: 15));
      } catch (_) {}
      try {
        await old
            // closeDatabase: false! С true закрывали файл из-под живых
            // таймлайнов/диалогов (forward-шеринг падал с database_closed
            // в getLocalizedDisplayname). Старый коннект просто бросаем,
            // новый клиент открывает свой к тому же файлу (WAL позволяет).
            .dispose(closeDatabase: false)
            .timeout(const Duration(seconds: 30));
      } catch (e, s) {
        Logs().w('[DB] dispose failed, continuing rebuild', e, s);
      }
      final fresh = await ClientManager.createClient(
        name,
        store,
      ).timeout(const Duration(seconds: 60));
      await fresh.initWithRestore().timeout(const Duration(seconds: 90));
      final i = widget.clients.indexOf(old);
      if (i != -1) widget.clients[i] = fresh;
      _cancelSubs(name);
      _registerSubs(name);
      TransportMimicry.instance.attach(fresh);
      if (wasActive) setActiveClient(fresh);
      final foreground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      fresh.backgroundSync = foreground;
      fresh.syncPresence = foreground
          ? PresenceType.online
          : PresenceType.offline;
      _lastDbRecovery = DateTime.now();
      Logs().i('[DB] Connection rebuilt, sync resumed for $name');
      _showDbRecoverySnack('Готово, синк пошёл.');
    } catch (e, s) {
      Logs().e('[DB] Recovery failed', e, s);
      _showDbRecoverySnack('Не вышло переподключить базу: $e');
    } finally {
      _dbRecovering = false;
    }
  }

  void _showDbRecoverySnack(String text) {
    try {
      final context =
          GAlMaxApp.router.routerDelegate.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text)));
    } catch (_) {}
  }

  void initMatrix() {
    for (final c in widget.clients) {
      _registerSubs(c.clientName);
      TransportMimicry.instance.attach(c);
    }

    if (PlatformInfos.isMobile) {
      backgroundPush = BackgroundPush(
        this,
        onFcmError: (errorMsg, {Uri? link}) async {
          final context =
              GAlMaxApp.router.routerDelegate.navigatorKey.currentContext ??
              this.context;
          if (!context.mounted) return;
          final result = await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).pushNotificationsNotAvailable,
            message: errorMsg,
            okLabel: link == null
                ? L10n.of(context).ok
                : L10n.of(context).learnMore,
            cancelLabel: L10n.of(context).doNotShowAgain,
          );
          if (result == OkCancelResult.ok && link != null) {
            launchUrlString(
              link.toString(),
              mode: LaunchMode.externalApplication,
            );
          }
          if (result == OkCancelResult.cancel) {
            await AppSettings.showNoGoogle.setItem(true);
          }
        },
      );
    }

    createVoipPlugin();
    // Трансляция трека в статус, если тумблер был включён раньше.
    // Передаём живые клиенты: сервис не умеет создавать их сам
    // (свежий Client без init всегда loggedOut).
    unawaited(
      MusicPresenceService().ensureStarted(clients: widget.clients),
    );
  }

  Future<void> createVoipPlugin() async {
    if (!AppSettings.experimentalVoip.value) {
      voipPlugin = null;
      return;
    }
    voipPlugin = VoipPlugin(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground =
        state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused;
    for (final client in widget.clients) {
      client.syncPresence = state == AppLifecycleState.resumed
          ? null
          : PresenceType.unavailable;
      if (PlatformInfos.isMobile) {
        client.backgroundSync = foreground;
        client.requestHistoryOnLimitedTimeline = !foreground;
        Logs().v('Set background sync to', foreground);
      }
    }
    // Вернулись в приложение — сразу обновить трек в статусе.
    if (state == AppLifecycleState.resumed) {
      unawaited(MusicPresenceService().tick(clients: widget.clients));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    for (final sub in onRoomKeyRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onKeyVerificationRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onLogoutSub.values) {
      sub.cancel();
    }
    for (final sub in onNotification.values) {
      sub.cancel();
    }
    for (final sub in onUiaRequest.values) {
      sub.cancel();
    }
    onRoomKeyRequestSub.clear();
    onKeyVerificationRequestSub.clear();
    onLogoutSub.clear();
    onNotification.clear();
    onUiaRequest.clear();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(create: (_) => this, child: widget.child);
  }

  Future<void> dehydrateAction(BuildContext context) async {
    final l10n = L10n.of(context);
    final response = await showOkCancelAlertDialog(
      context: context,
      isDestructive: true,
      title: l10n.dehydrate,
      message: l10n.dehydrateWarning,
    );
    if (response != OkCancelResult.ok) {
      return;
    }
    if (!context.mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: client.exportDump,
    );
    final export = result.result;
    if (export == null) return;

    final exportBytes = Uint8List.fromList(const Utf8Codec().encode(export));

    final exportFileName =
        'galmax-export-${DateFormat(DateFormat.YEAR_MONTH_DAY).format(DateTime.now())}.galmaxbackup';

    final file = MatrixFile(bytes: exportBytes, name: exportFileName);
    if (!context.mounted) return;
    file.save(context);
  }
}

class _AccountBundleWithClient {
  final Client? client;
  final AccountBundle? bundle;

  _AccountBundleWithClient({this.client, this.bundle});
}
