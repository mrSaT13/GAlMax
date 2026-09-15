import 'dart:io';

import 'package:galmax/config/app_config.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:galmax/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'settings_data_memory.dart';

class SettingsDataMemoryView extends StatefulWidget {
  final SettingsDataMemoryState controller;
  const SettingsDataMemoryView(this.controller, {super.key});

  @override
  State<SettingsDataMemoryView> createState() => _SettingsDataMemoryViewState();
}

class _SettingsDataMemoryViewState extends State<SettingsDataMemoryView> {
  bool _clearing = false;
  int _cachedImages = 0;
  int _cachedVideos = 0;
  int _cachedFiles = 0;
  int _totalCacheSize = 0;

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    final client = Matrix.of(context).client;
    int images = 0, videos = 0, files = 0;

    for (final room in client.rooms) {
      try {
        for (final stateEntry in room.states.values) {
          for (final event in stateEntry.values) {
            if (event.type == 'm.room.message') {
              final content = event.content;
              final msgtype = content['msgtype'];
              if (msgtype == 'm.image' || msgtype == 'm.sticker') {
                images++;
              } else if (msgtype == 'm.video') {
                videos++;
              } else {
                files++;
              }
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _cachedImages = images;
        _cachedVideos = videos;
        _cachedFiles = files;
        _totalCacheSize = images + videos + files;
      });
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить весь кэш?'),
        content: const Text(
          'Кэшированные данные будут удалены. Приложение продолжит работать normally.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);

    try {
      final client = Matrix.of(context).client;
      for (final room in client.rooms) {
        MxcImage.clearCache(room.id);
      }
      if (mounted) {
        await _calculateCacheSize();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кэш очищен')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearImagesCache() async {
    setState(() => _clearing = true);
    try {
      final client = Matrix.of(context).client;
      for (final room in client.rooms) {
        MxcImage.clearCache(room.id);
      }
      if (mounted) {
        await _calculateCacheSize();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Изображения удалены')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearVideosCache() async {
    setState(() => _clearing = true);
    try {
      final client = Matrix.of(context).client;
      for (final room in client.rooms) {
        MxcImage.clearCache(room.id);
      }
      if (mounted) {
        await _calculateCacheSize();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Видео удалены')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppConfig.darkBackground : null,
      appBar: AppBar(
        title: const Text('Данные и память'),
      ),
      body: ListView(
        children: [
          // Auto-download section
          _buildSection(
            context,
            title: 'Автозагрузка медиа',
            isDark: isDark,
            children: [
              SwitchListTile(
                title: const Text('Загружать автоматически'),
                value: true,
                onChanged: (v) {},
              ),
              _buildDivider(isDark),
              ListTile(
                title: const Text('Фото'),
                subtitle: const Text('Включено для всех чатов'),
                onTap: () {},
              ),
              _buildDivider(isDark),
              ListTile(
                title: const Text('Видео'),
                subtitle: const Text('Включено для всех чатов'),
                onTap: () {},
              ),
              _buildDivider(isDark),
              ListTile(
                title: const Text('Файлы'),
                subtitle: const Text('До 3.0 МБ для всех чатов'),
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Storage section
          _buildSection(
            context,
            title: 'Расчётный объём хранения',
            isDark: isDark,
            children: [
              _buildCacheRow(
                context,
                title: 'Кэшированные файлы',
                count: _totalCacheSize,
                onDelete: _clearAllCache,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildCacheItem(
                context,
                icon: Icons.photo,
                title: 'Фотографии',
                count: _cachedImages,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildCacheItem(
                context,
                icon: Icons.videocam,
                title: 'Видео',
                count: _cachedVideos,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildCacheItem(
                context,
                icon: Icons.insert_drive_file,
                title: 'Другое',
                count: _cachedFiles,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Clear all button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _clearing ? null : _clearAllCache,
              icon: _clearing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: const Text('Очистить весь кэш'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Кэшированные данные, необходимые для корректной работы приложения, не будут удалены.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              color: isDark ? AppConfig.darkCard : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheRow(
    BuildContext context, {
    required String title,
    required int count,
    required VoidCallback onDelete,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(title),
      subtitle: Text('$count файлов'),
      trailing: TextButton(
        onPressed: onDelete,
        child: const Text('Удалить', style: TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _buildCacheItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.6)),
      title: Text(title),
      subtitle: Text('$count файлов'),
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
