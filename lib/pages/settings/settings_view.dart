// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/settings/favorites_mode_tile.dart';
import 'package:galmax/utils/galmax_share.dart';
import 'package:galmax/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/widgets/app_background.dart';
import 'package:galmax/widgets/avatar.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:galmax/widgets/music_presence_tile.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../widgets/mxc_image_viewer.dart';
import 'settings.dart';

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final client = Matrix.of(context).client;
    final userId = client.userID ?? '';
    // Get display name from rooms where user is a member
    final displayName = client.rooms
        .where((room) => room.membership == Membership.join)
        .map((room) => room
            .getState(EventTypes.RoomMember, client.userID!)
            ?.content
            .tryGet<String>('displayname'))
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .firstOrNull ?? userId;

    return Scaffold(
      // Без override: фон берёт тема (иначе кастомный цвет не применяется),
      // поверх — локальный фон приложения, если выбран.
      body: Stack(
        children: [
          const AppBackground(),
          CustomScrollView(
        slivers: [
          // Profile header
          SliverToBoxAdapter(
            child: _buildProfileHeader(context, client, theme, isDark),
          ),

          // Account section
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: L10n.of(context).account,
              isDark: isDark,
              children: [
                _buildProfileTile(
                  context,
                  client: client,
                  isDark: isDark,
                ),
                _buildDivider(isDark),
                _buildAddAccountTile(context, client, isDark),
                _buildDivider(isDark),
                const MusicPresenceTile(),
              ],
            ),
          ),

          // Settings sections
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: null,
              isDark: isDark,
              children: [
                const FavoritesModeTile(),
                _buildDivider(isDark),
                _buildSettingsTile(
                  context,
                  icon: Icons.forum_outlined,
                  iconColor: Colors.blue,
                  title: L10n.of(context).chat,
                  subtitle: 'Текст, отправка, превью, эмодзи',
                  onTap: () => context.go('/rooms/settings/chat'),
                  isDark: isDark,
                ),
                _buildDivider(isDark),
                _buildSettingsTile(
                  context,
                  icon: Icons.lock_outline,
                  iconColor: Colors.green,
                  title: L10n.of(context).security,
                  subtitle: 'Время захода, устройства, ключи доступа',
                  onTap: () => context.go('/rooms/settings/security'),
                  isDark: isDark,
                ),
                _buildDivider(isDark),
                _buildSettingsTile(
                  context,
                  icon: Icons.notifications_outlined,
                  iconColor: Colors.red,
                  title: L10n.of(context).notifications,
                  subtitle: 'Звуки, звонки, счётчик сообщений',
                  onTap: () => context.go('/rooms/settings/notifications'),
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // Appearance section
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: null,
              isDark: isDark,
              children: [
                _buildSettingsTile(
                  context,
                  icon: Icons.format_paint_outlined,
                  iconColor: Colors.purple,
                  title: L10n.of(context).changeTheme,
                  subtitle: 'Цвета, обои, шрифты',
                  onTap: () => context.go('/rooms/settings/style'),
                  isDark: isDark,
                ),
                _buildDivider(isDark),
                _buildSettingsTile(
                  context,
                  icon: Icons.devices_outlined,
                  iconColor: Colors.teal,
                  title: L10n.of(context).devices,
                  subtitle: 'Управление устройствами',
                  onTap: () => context.go('/rooms/settings/devices'),
                  isDark: isDark,
                ),
                _buildDivider(isDark),
                _buildSettingsTile(
                  context,
                  icon: Icons.language_outlined,
                  iconColor: Colors.indigo,
                  title: 'Язык',
                  subtitle: 'Язык приложения',
                  onTap: () {},
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // Backup section
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: null,
              isDark: isDark,
              children: [
                _buildSwitchTile(
                  context,
                  icon: Icons.backup_outlined,
                  iconColor: Colors.cyan,
                  title: L10n.of(context).chatBackup,
                  subtitle: 'Резервное копирование ключей',
                  value: controller.cryptoIdentityConnected == true,
                  onChanged: controller.firstRunBootstrapAction,
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // Help section
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: null,
              isDark: isDark,
              children: [
                _buildSettingsTile(
                  context,
                  icon: Icons.help_outline,
                  iconColor: Colors.blueGrey,
                  title: L10n.of(context).help,
                  onTap: () => launchUrlString(AppConfig.helpUrl),
                  isDark: isDark,
                ),
                _buildDivider(isDark),
                _buildSettingsTile(
                  context,
                  icon: Icons.info_outline,
                  iconColor: Colors.grey,
                  title: L10n.of(context).about,
                  onTap: () async {
                    final info = await PackageInfo.fromPlatform();
                    if (context.mounted) {
                      final l10n = L10n.of(context);
                      showAboutDialog(
                        context: context,
                        applicationName: AppSettings.applicationName.value,
                        // Версия подтягивается из пакета (не захардкожена).
                        applicationVersion: info.version,
                        applicationIcon: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            './assets/logo/mini/logo_mini.png',
                            width: 48,
                            height: 48,
                          ),
                        ),
                        children: [
                          Text(
                            l10n.appSubtitle,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(l10n.appDescription),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => launchUrlString(
                              AppConfig.sourceCodeUrl,
                            ),
                            icon: const Icon(Icons.source_outlined),
                            label: Text(l10n.sourceCode),
                          ),
                        ],
                      );
                    }
                  },
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // Logout
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => controller.logoutAction(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(L10n.of(context).logout),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, Client client, ThemeData theme, bool isDark) {
    final userId = client.userID ?? '';
    // Get display name from rooms where user is a member
    final displayName = client.rooms
        .where((room) => room.membership == Membership.join)
        .map((room) => room
            .getState(EventTypes.RoomMember, client.userID!)
            ?.content
            .tryGet<String>('displayname'))
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .firstOrNull ?? userId;

    // Get avatar URL from rooms
    final avatarUrl = client.rooms
        .where((room) => room.membership == Membership.join)
        .map((room) => room
            .getState(EventTypes.RoomMember, client.userID!)
            ?.content
            .tryGet<String>('avatar_url'))
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .firstOrNull;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
      child: Column(
        children: [
          // Avatar: тап — смена (камера/галерея + кроп под круг).
          InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: controller.setAvatarAction,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Avatar(
                  mxContent: avatarUrl != null
                      ? Uri.tryParse(avatarUrl)
                      : null,
                  name: displayName,
                  size: 80,
                  client: client,
                  // Профиль: оригинал, иначе серверный тамбнейл отдаёт
                  // GIF статикой (1-й кадр).
                  fullRes: true,
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    size: 16,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Display name
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // Matrix ID
          Text(
            userId,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    String? title,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              // Цвет из темы, а не захардкоженный тёмно-зелёный:
              // иначе смена цвета не применяется к секциям.
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withOpacity(0.5),
                width: 0.5,
              ),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTile(
    BuildContext context, {
    required Client client,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    final userId = client.userID ?? '';
    // Get display name from rooms where user is a member
    final displayName = client.rooms
        .where((room) => room.membership == Membership.join)
        .map((room) => room
            .getState(EventTypes.RoomMember, client.userID!)
            ?.content
            .tryGet<String>('displayname'))
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .firstOrNull ?? userId;

    // Get avatar URL from rooms
    final avatarUrl = client.rooms
        .where((room) => room.membership == Membership.join)
        .map((room) => room
            .getState(EventTypes.RoomMember, client.userID!)
            ?.content
            .tryGet<String>('avatar_url'))
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .firstOrNull;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Avatar(
        mxContent: avatarUrl != null ? Uri.tryParse(avatarUrl) : null,
        name: displayName,
        size: 48,
        client: client,
      ),
      title: Text(
        displayName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        userId,
        style: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurface.withOpacity(0.4),
      ),
      onTap: () {},
    );
  }

  Widget _buildAddAccountTile(BuildContext context, Client currentClient, bool isDark) {
    final theme = Theme.of(context);
    final matrix = Matrix.of(context);
    final allClients = <Client>[];
    matrix.accountBundles.forEach((key, value) {
      for (final c in value) {
        if (c is Client && c.isLogged()) allClients.add(c);
      }
    });
    final hasMultiple = allClients.length > 1;

    return Column(
      children: [
        if (hasMultiple)
          for (final otherClient in allClients)
            if (otherClient.userID != currentClient.userID)
              FutureBuilder<Profile?>(
                future: otherClient.fetchOwnProfile(),
                builder: (context, snapshot) {
                  final name = snapshot.data?.displayName ?? otherClient.userID!.localpart!;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Avatar(
                      mxContent: snapshot.data?.avatarUrl,
                      name: name,
                      size: 36,
                    ),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      otherClient.userID ?? '',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                      size: 20,
                    ),
                    onTap: () {
                      matrix.setActiveClient(otherClient);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.person_add_outlined,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
          title: Text(
            L10n.of(context).addAccount,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurface.withOpacity(0.3),
            size: 20,
          ),
          onTap: () => context.go('/rooms/settings/addaccount'),
        ),
      ],
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? theme.colorScheme.primary).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? theme.colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurface.withOpacity(0.3),
        size: 20,
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? theme.colorScheme.primary).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? theme.colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            )
          : null,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 52,
      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
    );
  }
}
