// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/config/themes.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/settings_notifications/push_rule_extensions.dart';
import 'package:galmax/utils/background_sync.dart';
import 'package:galmax/utils/push_helper.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:galmax/widgets/layouts/max_width_body.dart';
import 'package:galmax/widgets/settings_switch_list_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

import '../../utils/localized_exception_extension.dart';
import '../../widgets/matrix.dart';
import 'settings_notifications.dart';

class SettingsNotificationsView extends StatelessWidget {
  final SettingsNotificationsController controller;

  const SettingsNotificationsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final pushRules = Matrix.of(context).client.globalPushRules;
    final pushCategories = [
      if (pushRules?.override?.isNotEmpty ?? false)
        (rules: pushRules?.override ?? [], kind: PushRuleKind.override),
      if (pushRules?.content?.isNotEmpty ?? false)
        (rules: pushRules?.content ?? [], kind: PushRuleKind.content),
      if (pushRules?.sender?.isNotEmpty ?? false)
        (rules: pushRules?.sender ?? [], kind: PushRuleKind.sender),
      if (pushRules?.underride?.isNotEmpty ?? false)
        (rules: pushRules?.underride ?? [], kind: PushRuleKind.underride),
    ];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !GalmaxThemes.isColumnMode(context),
        centerTitle: GalmaxThemes.isColumnMode(context),
        title: Text(L10n.of(context).notifications),
      ),
      body: MaxWidthBody(
        child: StreamBuilder(
          stream: Matrix.of(context).client.onSync.stream.where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.push_rules',
                ) ??
                false,
          ),
          builder: (BuildContext context, _) {
            final theme = Theme.of(context);
            final lastReceivedPush =
                lastReceivedPushNotification[Matrix.of(
                  context,
                ).client.clientName];
            return SelectionArea(
              child: Column(
                children: [
                  // Push delivery method
                  ListTile(
                    leading: Icon(
                      Icons.notifications_active_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text(
                      'Способ доставки уведомлений',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text(
                      'Google Services (FCM) или UnifiedPush (ntfy)',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                    onTap: () => _showPushDeliveryDialog(context),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.dividerColor,
                  ),
                  // Fallback sync when FCM / UnifiedPush are unavailable
                  const _BackgroundSyncTile(),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.dividerColor,
                  ),
                  if (kDebugMode && lastReceivedPush != null)
                    ListTile(
                      title: Text('Last received push notification'),
                      subtitle: Text(lastReceivedPush.toIso8601String()),
                    ),
                  if (kIsWeb)
                    SettingsSwitchListTile.adaptive(
                      title: L10n.of(context).playSoundOnNotification,
                      setting: AppSettings.webNotificationSound,
                    ),
                  if (!kIsWeb) const _NotificationSoundTile(),
                  if (pushRules != null)
                    for (final category in pushCategories) ...[
                      ListTile(
                        title: Text(
                          category.kind.localized(L10n.of(context)),
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      for (final rule in category.rules)
                        ListTile(
                          title: Text(rule.getPushRuleName(L10n.of(context))),
                          subtitle: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: rule.getPushRuleDescription(
                                    L10n.of(context),
                                  ),
                                ),
                                const TextSpan(text: ' '),
                                WidgetSpan(
                                  child: InkWell(
                                    onTap: () => controller.editPushRule(
                                      rule,
                                      category.kind,
                                    ),
                                    child: Text(
                                      L10n.of(context).more,
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                        decorationColor:
                                            theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Switch.adaptive(
                            value: rule.enabled,
                            onChanged: controller.isLoading
                                ? null
                                : rule.ruleId != '.m.rule.master' &&
                                      Matrix.of(
                                        context,
                                      ).client.allPushNotificationsMuted
                                ? null
                                : (_) => controller.togglePushRule(
                                    category.kind,
                                    rule,
                                  ),
                          ),
                        ),
                      Divider(color: theme.dividerColor),
                    ],
                  ListTile(
                    title: Text(
                      L10n.of(context).devices,
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FutureBuilder<List<Pusher>?>(
                    future: controller.pusherFuture ??= Matrix.of(
                      context,
                    ).client.getPushers(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        Center(
                          child: Text(
                            snapshot.error!.toLocalizedString(context),
                          ),
                        );
                      }
                      if (snapshot.connectionState != ConnectionState.done) {
                        const Center(
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        );
                      }
                      final pushers = snapshot.data ?? [];
                      if (pushers.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Text(L10n.of(context).noOtherDevicesFound),
                          ),
                        );
                      }
                      return ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: pushers.length,
                        itemBuilder: (_, i) => ListTile(
                          title: Text(
                            '${pushers[i].appDisplayName} - ${pushers[i].appId}',
                          ),
                          subtitle: Text(pushers[i].data.url.toString()),
                          onTap: () => controller.onPusherTap(pushers[i]),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showPushDeliveryDialog(BuildContext context) {
    final theme = Theme.of(context);
    final matrix = Matrix.of(context);
    final isUnifiedPushRegistered = AppSettings.unifiedPushRegistered.value;
    final isFirebaseAvailable = matrix.backgroundPush?.firebaseEnabled ?? false;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Способ доставки уведомлений'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.g_mobiledata, color: Colors.blue),
              ),
              title: const Text('Google Services (FCM)'),
              subtitle: Text(
                isFirebaseAvailable
                    ? 'Активен. Быстрая доставка через Firebase.'
                    : 'Firebase недоступен на этом устройстве.',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: isFirebaseAvailable
                  ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                  : const Icon(Icons.cancel, color: Colors.red, size: 20),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isFirebaseAvailable
                          ? 'FCM уже активен'
                          : 'Firebase недоступен на этом устройстве. Установите Google Play Services или используйте UnifiedPush.',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.green),
              ),
              title: const Text('UnifiedPush (ntfy)'),
              subtitle: Text(
                isUnifiedPushRegistered
                    ? 'Активен. Приватный вариант без Google.'
                    : 'Требует установки ntfy или аналога.',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: isUnifiedPushRegistered
                  ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                  : null,
              onTap: () async {
                Navigator.pop(context);
                if (isUnifiedPushRegistered) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('UnifiedPush уже активен'),
                    ),
                  );
                } else {
                  // Try to setup UnifiedPush
                  try {
                    await matrix.backgroundPush?.setupPush();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('UnifiedPush настроен. Установите ntfy для получения уведомлений.'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Ошибка настройки UnifiedPush: $e'),
                        ),
                      );
                    }
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Builder(
              builder: (tileContext) {
                final gateway = AppSettings.pushNotificationsGatewayUrl.value;
                final isDefault =
                    gateway ==
                    AppSettings.pushNotificationsGatewayUrl.defaultValue;
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.cloud_outlined,
                    color: Colors.orange,
                  ),
                  title: const Text(
                    'Push-шлюз',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    gateway,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: isDefault
                      ? null
                      : IconButton(
                          tooltip: 'Сбросить',
                          icon: const Icon(Icons.restart_alt_outlined, size: 20),
                          onPressed: () async {
                            await AppSettings.pushNotificationsGatewayUrl
                                .setItem(
                                  AppSettings
                                      .pushNotificationsGatewayUrl
                                      .defaultValue,
                                );
                            if (tileContext.mounted) {
                              Navigator.of(tileContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Шлюз сброшен. Нажми «Починить», чтобы перерегистрировать пушеры.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                  onTap: () async {
                    final input = await showTextInputDialog(
                      context: tileContext,
                      title: 'Push-шлюз',
                      okLabel: 'OK',
                      cancelLabel: 'Отмена',
                      initialText: gateway,
                    );
                    if (input == null || !tileContext.mounted) return;
                    final url = input.trim().isEmpty
                        ? AppSettings.pushNotificationsGatewayUrl.defaultValue
                        : input.trim();
                    await AppSettings.pushNotificationsGatewayUrl.setItem(url);
                    if (tileContext.mounted) {
                      Navigator.of(tileContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Шлюз сменён. Нажми «Починить», чтобы перерегистрировать пушеры.',
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await matrix.backgroundPush?.repairPushers();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Пушеры пересозданы. Проверь список устройств ниже.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toLocalizedString(context))),
                  );
                }
              }
            },
            child: const Text('Починить'),
          ),
        ],
      ),
    );
  }
}

/// Выбор и вкл/выкл звука уведомлений (Android raw + iOS caf).
/// На Android 8+ звук применяется через пересоздание канала.
class _NotificationSoundTile extends StatefulWidget {
  const _NotificationSoundTile();

  @override
  State<_NotificationSoundTile> createState() => _NotificationSoundTileState();
}

class _NotificationSoundTileState extends State<_NotificationSoundTile> {
  static const _sounds = <String, String>{
    'notification': 'По умолчанию',
    'call': 'Звонок',
    'phone': 'Телефон',
    'system': 'Системный',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = AppSettings.notificationSoundEnabled.value;
    final current = AppSettings.notificationSoundName.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile.adaptive(
          secondary: Icon(
            enabled ? Icons.volume_up_outlined : Icons.volume_off_outlined,
            color: theme.colorScheme.primary,
          ),
          title: const Text(
            'Звук уведомлений',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            enabled
                ? (_sounds[current] ?? current)
                : 'Выключен (только вибрация)',
            style: const TextStyle(fontSize: 12),
          ),
          value: enabled,
          onChanged: (v) async {
            await AppSettings.notificationSoundEnabled.setItem(v);
            if (mounted) setState(() {});
          },
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final entry in _sounds.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: current == entry.key,
                      onSelected: (_) async {
                        await AppSettings.notificationSoundName.setItem(
                          entry.key,
                        );
                        if (mounted) setState(() {});
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Звук применён. На Android 8+ может потребоваться перезапуск.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Fallback periodic sync toggle + manual "check now".
/// Works without FCM / UnifiedPush via a foreground service on Android.
class _BackgroundSyncTile extends StatefulWidget {  const _BackgroundSyncTile();

  @override
  State<_BackgroundSyncTile> createState() => _BackgroundSyncTileState();
}

class _BackgroundSyncTileState extends State<_BackgroundSyncTile> {
  bool? _enabled;
  bool _syncing = false;
  bool _testing = false;
  int _interval = 15;

  static const _intervalOptions = [1, 2, 5, 15, 30];

  @override
  void initState() {
    super.initState();
    BackgroundSyncService.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
    _interval = AppSettings.backgroundSyncIntervalMinutes.value;
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    try {
      await BackgroundSyncService.setEnabled(value);
    } catch (_) {}
    if (!mounted) return;
    final actual = await BackgroundSyncService.isEnabled();
    if (mounted) setState(() => _enabled = actual);
  }

  Future<void> _checkNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    String? errorText;
    String? details;
    try {
      final report = await BackgroundSyncService.syncNow().timeout(
        const Duration(seconds: 90),
      );
      if (report.skipped) {
        details = 'Пропущено: синк уже идёт, попробуй через пару секунд.';
      } else if (report.error != null) {
        errorText = report.error;
        details =
            'Проверено клиентов: ${report.clientsChecked}, комнат: ${report.roomsScanned}.';
      } else {
        details =
            'Проверено клиентов: ${report.clientsChecked}, комнат: ${report.roomsScanned}, уведомлений: ${report.notified}.';
        if (report.notified == 0) {
          details =
              '$details Если ждал сообщение, а его нет даже в списке чатов — синк его не fetched (смотри /logs), либо комната прочитанная/замьюченная (notificationCount=0).';
        }
      }
    } catch (e) {
      errorText = e.toString();
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errorText == null
              ? '${L10n.of(context).syncNow}: OK. $details'
              : '${L10n.of(context).syncNow}: ошибка: $errorText ${details ?? ''}',
        ),
      ),
    );
  }

  Future<void> _setInterval(int minutes) async {
    if (_interval == minutes) return;
    setState(() => _interval = minutes);
    try {
      await BackgroundSyncService.setIntervalMinutes(minutes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          minutes <= 2
              ? 'Проверка каждые $minutes мин. Жрёт батарею — следи.'
              : 'Проверка каждые $minutes мин.',
        ),
      ),
    );
  }

  /// Прямой тест канала/разрешений без зависимости от синка и непрочитанных.
  Future<void> _testNotification() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('notifications_icon'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      try {
        await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } catch (_) {}
      try {
        final l10n = L10n.of(context);
        await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              AndroidNotificationChannel(
                AppConfig.pushNotificationsChannelId,
                l10n.incomingMessages,
                description: 'Notifications for new messages',
                importance: Importance.high,
                enableVibration: true,
                playSound: AppSettings.notificationSoundEnabled.value,
                sound: notificationSound(),
              ),
            );
      } catch (_) {}
      await plugin.show(
        id: 9999,
        title: 'GAlMax: тестовое уведомление',
        body:
            'Канал и разрешения в порядке. Кнопка рядом ищет реальные непрочитанные.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            AppConfig.pushNotificationsChannelId,
            L10n.of(context).incomingMessages,
            importance: Importance.high,
            priority: Priority.high,
            playSound: AppSettings.notificationSoundEnabled.value,
            sound: notificationSound(),
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: AppSettings.notificationSoundEnabled.value,
          ),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тестовое показано. Не видишь — проверь разрешения/канал.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _enabled ?? true;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile.adaptive(
          secondary: Icon(
            Icons.sync_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            L10n.of(context).backgroundSync,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            L10n.of(context).backgroundSyncDescription,
            style: const TextStyle(fontSize: 12),
          ),
          value: enabled,
          onChanged: _enabled == null ? null : _toggle,
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in _intervalOptions)
                        ChoiceChip(
                          label: Text(m == 1 ? '1 мин' : '$m мин'),
                          selected: _interval == m,
                          onSelected: (_) => _setInterval(m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Чаще — быстрее сообщения без Firebase, но больше расход батареи.',
                    style: TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _syncing ? null : _checkNow,
                        icon: _syncing
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(L10n.of(context).syncNow),
                      ),
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _testNotification,
                        icon: _testing
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.notifications_outlined, size: 18),
                        label: const Text('Тест'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
