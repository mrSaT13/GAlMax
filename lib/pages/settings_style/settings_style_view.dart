// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/config/themes.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/chat/events/state_message.dart';
import 'package:galmax/utils/account_config.dart';
import 'package:galmax/utils/color_value.dart';
import 'package:galmax/widgets/avatar.dart';
import 'package:galmax/widgets/layouts/max_width_body.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:galmax/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../config/app_config.dart';
import 'settings_style.dart';

class SettingsStyleView extends StatelessWidget {
  final SettingsStyleController controller;

  const SettingsStyleView(this.controller, {super.key});

  void _showCustomColorPicker(BuildContext context) {
    final currentColor = controller.currentColor ?? AppConfig.chatColor;
    showDialog(
      context: context,
      builder: (context) => _CustomColorPickerDialog(
        initialColor: currentColor,
        onColorSelected: (color) => controller.setChatColor(color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const colorPickerSize = 32.0;
    final client = Matrix.of(context).client;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !GalmaxThemes.isColumnMode(context),
        centerTitle: GalmaxThemes.isColumnMode(context),
        title: Text(L10n.of(context).changeTheme),
      ),
      backgroundColor: theme.colorScheme.surface,
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: SegmentedButton<ThemeMode>(
                selected: {controller.currentTheme},
                onSelectionChanged: (selected) =>
                    controller.switchTheme(selected.single),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(L10n.of(context).lightTheme),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(L10n.of(context).darkTheme),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(L10n.of(context).systemTheme),
                    icon: const Icon(Icons.auto_mode_outlined),
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).setColorTheme,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Curated preset themes: one tap sets the whole app palette.
            _PresetThemeRow(
              currentColor: controller.currentColor,
              onSelect: controller.setChatColor,
            ),
            DynamicColorBuilder(
              builder: (light, dark) {
                final systemColor =
                    Theme.of(context).brightness == Brightness.light
                    ? light?.primary
                    : dark?.primary;
                final colors = [null, AppConfig.chatColor, ...Colors.primaries];
                if (systemColor == null) {
                  colors.remove(null);
                }
                return Column(
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 64,
                      ),
                      itemCount: colors.length,
                      itemBuilder: (context, i) {
                        final color = colors[i];
                        return Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Tooltip(
                            message: color == null
                                ? L10n.of(context).systemTheme
                                : '#${color.hexValue.toRadixString(16).toUpperCase()}',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(colorPickerSize),
                              onTap: () => controller.setChatColor(color),
                              child: Material(
                                color: color ?? systemColor,
                                elevation: 6,
                                borderRadius: BorderRadius.circular(
                                  colorPickerSize,
                                ),
                                child: SizedBox(
                                  width: colorPickerSize,
                                  height: colorPickerSize,
                                  child: controller.currentColor == color
                                      ? Center(
                                          child: Icon(
                                            Icons.check,
                                            size: 16,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.palette_outlined,
                          color: theme.colorScheme.secondary,
                        ),
                        title: Text(L10n.of(context).chooseCustomColor),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _showCustomColorPicker(context),
                      ),
                    ),
                  ],
                );
              },
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).messagesStyle,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            StreamBuilder(
              stream: client.onSync.stream.where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) =>
                          accountData.type ==
                          ApplicationAccountConfigExtension.accountDataKey,
                    ) ??
                    false,
              ),
              builder: (context, snapshot) {
                final accountConfig = client.applicationAccountConfig;

                return StatefulBuilder(
                  builder: (context, setState) => Column(
                  mainAxisSize: .min,
                  children: [
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(
                          AppSettings.fontSizeFactor.value,
                        ),
                      ),
                      child: AnimatedContainer(
                        duration: GalmaxThemes.animationDuration,
                        curve: GalmaxThemes.animationCurve,
                        decoration: const BoxDecoration(),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (accountConfig.wallpaperUrl != null)
                              Opacity(
                                opacity: controller.wallpaperOpacity,
                                child: ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: controller.wallpaperBlur,
                                    sigmaY: controller.wallpaperBlur,
                                  ),
                                  child: MxcImage(
                                    key: ValueKey(accountConfig.wallpaperUrl),
                                    uri: accountConfig.wallpaperUrl,
                                    fit: BoxFit.cover,
                                    isThumbnail: true,
                                    width: GalmaxThemes.columnWidth * 2,
                                    height: 212,
                                  ),
                                ),
                              ),
                            Column(
                              mainAxisSize: .min,
                              children: [
                                const SizedBox(height: 16),
                                StateMessage(
                                  Event(
                                    eventId: 'style_dummy',
                                    room: Room(
                                      id: '!style_dummy',
                                      client: client,
                                    ),
                                    content: {'membership': 'join'},
                                    type: EventTypes.RoomMember,
                                    senderId: client.userID!,
                                    originServerTs: DateTime.now(),
                                    stateKey: client.userID,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: 12 + 12 + Avatar.defaultSize,
                                    right: 12,
                                    top: accountConfig.wallpaperUrl == null
                                        ? 0
                                        : 12,
                                    bottom: 12,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: theme.bubbleColor,
                                      borderRadius: BorderRadius.circular(
                                        AppSettings.cornerRadius.value,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor',
                                        style: TextStyle(
                                          color: theme.onBubbleColor,
                                          fontSize: AppConfig.messageFontSize,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: 12,
                                      left: 12,
                                      top: accountConfig.wallpaperUrl == null
                                          ? 0
                                          : 12,
                                      bottom: 12,
                                    ),
                                    child: Material(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(
                                        AppSettings.cornerRadius.value,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'Lorem ipsum dolor sit amet',
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                            fontSize: AppConfig.messageFontSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(color: theme.dividerColor),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Углы блоков с сообщениями',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${AppSettings.cornerRadius.value.round()}',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: AppSettings.cornerRadius.value,
                            min: 0,
                            max: 32,
                            divisions: 32,
                            activeColor: theme.colorScheme.primary,
                            onChanged: (value) {
                              AppSettings.cornerRadius.setItem(value);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          foregroundColor:
                              theme.colorScheme.onSecondaryContainer,
                        ),
                        onPressed: controller.setWallpaper,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(L10n.of(context).setWallpaper),
                      ),
                      trailing: accountConfig.wallpaperUrl == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outlined),
                              color: theme.colorScheme.error,
                              onPressed: controller.deleteChatWallpaper,
                            ),
                    ),
                    // Локальный фон приложения (не синхронизируется).
                    // Та же форма, что у «Установить обои» выше.
                    ListTile(
                      title: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          foregroundColor:
                              theme.colorScheme.onSecondaryContainer,
                        ),
                        onPressed: controller.setLocalBackground,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text(
                          'Фон приложения (только это устройство)',
                        ),
                      ),
                      trailing:
                          AppSettings.chatLocalBackgroundPath.value.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outlined),
                              color: theme.colorScheme.error,
                              onPressed: controller.deleteLocalBackground,
                            ),
                    ),
                    if (AppSettings
                        .chatLocalBackgroundPath
                        .value
                        .isNotEmpty) ...[
                      ListTile(title: const Text('Прозрачность фона')),
                      Slider.adaptive(
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        value: AppSettings.chatLocalBackgroundOpacity.value,
                        onChanged: (v) async {
                          await AppSettings.chatLocalBackgroundOpacity.setItem(
                            v,
                          );
                          controller.updateWallpaperOpacity(
                            controller.wallpaperOpacity,
                          );
                        },
                      ),
                      ListTile(title: const Text('Размытие фона')),
                      Slider.adaptive(
                        min: 0.0,
                        max: 12.0,
                        divisions: 12,
                        value: AppSettings.chatLocalBackgroundBlur.value,
                        onChanged: (v) async {
                          await AppSettings.chatLocalBackgroundBlur.setItem(v);
                          controller.updateWallpaperOpacity(
                            controller.wallpaperOpacity,
                          );
                        },
                      ),
                    ],
                    if (accountConfig.wallpaperUrl != null) ...[
                      ListTile(title: Text(L10n.of(context).opacity)),
                      Slider.adaptive(
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperOpacity,
                        onChanged: controller.updateWallpaperOpacity,
                        onChangeEnd: controller.saveWallpaperOpacity,
                      ),
                      ListTile(title: Text(L10n.of(context).blur)),
                      Slider.adaptive(
                        min: 0.0,
                        max: 10.0,
                        divisions: 10,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperBlur,
                        onChanged: controller.updateWallpaperBlur,
                        onChangeEnd: controller.saveWallpaperBlur,
                      ),
                    ],
                  ],
                ),
                );
              },
            ),
            ListTile(
              title: Text(L10n.of(context).fontSize),
              trailing: Text('× ${AppSettings.fontSizeFactor.value}'),
            ),
            Slider.adaptive(
              min: 0.5,
              max: 2.5,
              divisions: 20,
              value: AppSettings.fontSizeFactor.value,
              semanticFormatterCallback: (d) => d.toString(),
              onChanged: controller.changeFontSizeFactor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Curated one-tap themes: name + seed color (null = system dynamic color).
class _PresetThemeRow extends StatelessWidget {
  final Color? currentColor;
  final void Function(Color?) onSelect;

  const _PresetThemeRow({required this.currentColor, required this.onSelect});

  static const _presets = <String, int?>{
    'GAlMax': 0xFF2E7D32,
    'Ocean': 0xFF1565C0,
    'Sunset': 0xFFE65100,
    'Violet': 0xFF6A1B9A,
    'Rose': 0xFFC2185B,
    'Slate': 0xFF546E7A,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final entry in _presets.entries)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => onSelect(Color(entry.value!)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(entry.value!),
                            Color.lerp(
                              Color(entry.value!),
                              Colors.white,
                              0.45,
                            )!,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: currentColor == Color(entry.value!)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: currentColor == Color(entry.value!) ? 3 : 1,
                        ),
                      ),
                      child: currentColor == Color(entry.value!)
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface,
                        fontWeight:
                            currentColor == Color(entry.value!)
                                ? FontWeight.w700
                                : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomColorPickerDialog extends StatefulWidget {  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const _CustomColorPickerDialog({
    required this.initialColor,
    required this.onColorSelected,
  });

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late Color _selectedColor;
  late double _hue;
  late double _saturation;
  late double _value;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    final hsv = HSVColor.fromColor(_selectedColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
  }

  void _updateFromHSV() {
    setState(() {
      _selectedColor = HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(L10n.of(context).chooseCustomColor),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _selectedColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.outline,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '#${_selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),
            Text(L10n.of(context).hue, style: theme.textTheme.bodySmall),
            Slider(
              value: _hue,
              min: 0,
              max: 360,
              divisions: 360,
              activeColor: _selectedColor,
              onChanged: (v) {
                _hue = v;
                _updateFromHSV();
              },
            ),
            Text(L10n.of(context).saturation, style: theme.textTheme.bodySmall),
            Slider(
              value: _saturation,
              min: 0,
              max: 1,
              divisions: 100,
              activeColor: _selectedColor,
              onChanged: (v) {
                _saturation = v;
                _updateFromHSV();
              },
            ),
            Text(L10n.of(context).brightness, style: theme.textTheme.bodySmall),
            Slider(
              value: _value,
              min: 0,
              max: 1,
              divisions: 100,
              activeColor: _selectedColor,
              onChanged: (v) {
                _value = v;
                _updateFromHSV();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).cancel),
        ),
        TextButton(
          onPressed: () {
            widget.onColorSelected(_selectedColor);
            Navigator.of(context).pop();
          },
          child: Text(L10n.of(context).ok),
        ),
      ],
    );
  }
}
