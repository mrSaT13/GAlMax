// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/themes.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/favorites_helper.dart';
import 'package:galmax/utils/localized_exception_extension.dart';
import 'package:galmax/widgets/layouts/max_width_body.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:galmax/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

/// Избранное, хранящееся только на этом устройстве.
/// Серверный режим открывает обычную комнату с собой, сюда не попадает.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  Future<List<FavoriteItem>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = FavoritesHelper.getLocalFavorites(Matrix.of(context).client);
  }

  Future<void> _delete(FavoriteItem item) async {
    try {
      await FavoritesHelper.removeLocalFavorite(
        Matrix.of(context).client,
        item.id,
      );
      if (mounted) setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !GalmaxThemes.isColumnMode(context),
        centerTitle: GalmaxThemes.isColumnMode(context),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, color: Colors.amber, size: 20),
            SizedBox(width: 6),
            Text('Избранное'),
          ],
        ),
      ),
      body: MaxWidthBody(
        child: FutureBuilder<List<FavoriteItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_border_outlined,
                        size: 64,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Пока пусто. Долгое нажатие на сообщение → «В избранное».',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Хранится только на этом устройстве.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, i) =>
                  _FavoriteTile(item: items[i], onDelete: () => _delete(items[i])),
            );
          },
        ),
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  final FavoriteItem item;
  final VoidCallback onDelete;

  const _FavoriteTile({required this.item, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final date = DateTime.fromMillisecondsSinceEpoch(item.ts);
    final isImage =
        (item.mimetype?.startsWith('image/') ?? false) && item.url != null;
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outlined,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            isImage ? Icons.image_outlined : Icons.star_outlined,
            color: theme.colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: isImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MxcImage(
                  uri: Uri.tryParse(item.url!),
                  client: client,
                  fit: BoxFit.cover,
                  width: 220,
                  height: 140,
                  isThumbnail: true,
                  animated: false,
                ),
              )
            : Text(item.body, maxLines: 4, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${item.senderName} • ${item.roomName} • ${DateFormat.Hm().add_yMd().format(date)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          tooltip: L10n.of(context).delete,
          icon: const Icon(Icons.delete_outlined, size: 20),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
