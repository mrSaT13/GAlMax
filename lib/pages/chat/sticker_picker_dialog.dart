// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/bundled_stickers.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/localized_exception_extension.dart';
import 'package:galmax/utils/url_launcher.dart';
import 'package:galmax/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/avatar.dart';

class StickerPickerDialog extends StatefulWidget {
  final Room room;
  final Future<void> Function(ImagePackImageContent) onSelected;

  const StickerPickerDialog({
    required this.onSelected,
    required this.room,
    super.key,
  });

  @override
  StickerPickerDialogState createState() => StickerPickerDialogState();
}

class StickerPickerDialogState extends State<StickerPickerDialog> {
  String? searchFilter;
  bool _uploadingBundled = false;

  /// Встроенный пак: картинка из assets -> загрузка на хомсервер -> обычный
  /// m.sticker. Дальше всё штатно (диалог доверия, отправка).
  Future<void> _sendBundled(BundledSticker sticker) async {
    if (_uploadingBundled) return;
    setState(() => _uploadingBundled = true);
    try {
      final bytes = (await rootBundle.load(
        sticker.assetPath,
      )).buffer.asUint8List();
      // Ранняя проверка лимита хомсервера, иначе upload упадёт generic-ошибкой.
      try {
        final config = await widget.room.client.getConfig();
        final maxSize = config.mUploadSize;
        if (maxSize != null && bytes.length > maxSize) {
          throw FileTooBigMatrixException(bytes.length, maxSize);
        }
      } catch (e) {
        if (e is FileTooBigMatrixException) rethrow;
        // getConfig может не поддерживаться — тогда просто пробуем upload.
        Logs().d('[Sticker] getConfig failed, trying upload anyway', e);
      }
      final mxc = await widget.room.client.uploadContent(
        bytes,
        filename: sticker.assetPath.split('/').last,
        contentType: sticker.mimeType,
      );
      Logs().d(
        '[Sticker] uploaded ${sticker.assetPath} mime=${sticker.mimeType} size=${bytes.length} -> $mxc',
      );
      await widget.onSelected(
        ImagePackImageContent.fromJson({
          'body': sticker.name,
          'url': mxc.toString(),
          'info': {'mimetype': sticker.mimeType, 'size': bytes.length},
        }),
      );
    } catch (e, s) {
      Logs().e('[Sticker] sendBundled failed ${sticker.assetPath}', e, s);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      }
    } finally {
      if (mounted) setState(() => _uploadingBundled = false);
    }
  }

  bool _matchesFilter(String name) {
    final f = searchFilter;
    if (f == null || f.isEmpty) return true;
    return name.toLowerCase().contains(f.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final stickerPacks = widget.room.getImagePacks(ImagePackUsage.sticker);
    final packSlugs = stickerPacks.keys.toList();
    // Встроенные паки с фильтром по поиску; пустые разделы прячем.
    final bundledPacks = [
      for (final pack in bundledStickerPacks)
        BundledStickerPack(
          pack.title,
          pack.items.where((s) => _matchesFilter(s.name)).toList(),
        ),
    ].where((pack) => pack.items.isNotEmpty).toList();
    final hasBundled = bundledPacks.isNotEmpty;

    return Material(
      color: theme.colorScheme.onInverseSurface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Поиск всегда сверху, как в GIF-пикере: обычный виджет,
            // а не SliverAppBar (тот давал гуляющий отступ посреди секции).
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: L10n.of(context).search,
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.normal,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    prefixIcon: const Icon(Icons.search_outlined, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (s) => setState(() => searchFilter = s),
                ),
              ),
            ),
            Expanded(
              child: packSlugs.isEmpty && !hasBundled
                  ? Center(
                      child: Column(
                        mainAxisSize: .min,
                        children: [
                          Text(L10n.of(context).noEmotesFound),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => UrlLauncher(
                              context,
                              AppConfig.howDoIGetStickersTutorial,
                            ).launchUrl(),
                            icon: const Icon(Icons.explore_outlined),
                            label: Text(L10n.of(context).discover),
                          ),
                        ],
                      ),
                    )
                  : CustomScrollView(
                      slivers: <Widget>[
                        if (hasBundled)
                          SliverToBoxAdapter(
                            child: _buildBundledPack(context, bundledPacks),
                          ),
                        SliverList.builder(
                          itemCount: packSlugs.length,
                          itemBuilder: (BuildContext context, int packIndex) {
                            final pack = stickerPacks[packSlugs[packIndex]]!;
                            final filteredImagePackImageEntried = pack
                                .images
                                .entries
                                .toList();
                            if (searchFilter?.isNotEmpty ?? false) {
                              filteredImagePackImageEntried.removeWhere(
                                (e) =>
                                    !(e.key.toLowerCase().contains(
                                          searchFilter!.toLowerCase(),
                                        ) ||
                                        (e.value.body?.toLowerCase().contains(
                                              searchFilter!.toLowerCase(),
                                            ) ??
                                            false)),
                              );
                            }
                            final imageKeys = filteredImagePackImageEntried
                                .map((e) => e.key)
                                .toList();
                            if (imageKeys.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final packName =
                                pack.pack.displayName ?? packSlugs[packIndex];
                            return Column(
                              children: <Widget>[
                                if (packIndex != 0) const SizedBox(height: 20),
                                if (packName != 'user')
                                  ListTile(
                                    leading: Avatar(
                                      mxContent: pack.pack.avatarUrl,
                                      name: packName,
                                      client: widget.room.client,
                                    ),
                                    title: Text(packName),
                                  ),
                                const SizedBox(height: 6),
                                GridView.builder(
                                  itemCount: imageKeys.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 84,
                                        mainAxisSpacing: 8.0,
                                        crossAxisSpacing: 8.0,
                                      ),
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemBuilder:
                                      (BuildContext context, int imageIndex) {
                                        final image =
                                            pack.images[imageKeys[imageIndex]]!;
                                        return Tooltip(
                                          message:
                                              image.body ??
                                              imageKeys[imageIndex],
                                          child: InkWell(
                                            radius: AppConfig.borderRadius,
                                            key: ValueKey(image.url.toString()),
                                            onTap: () {
                                              // copy the image
                                              final imageCopy =
                                                  ImagePackImageContent.fromJson(
                                                    image.toJson().copy(),
                                                  );
                                              // set the body, if it doesn't exist, to the key
                                              imageCopy.body ??=
                                                  imageKeys[imageIndex];
                                              widget.onSelected(imageCopy);
                                            },
                                            child: AbsorbPointer(
                                              absorbing: true,
                                              child: MxcImage(
                                                uri: image.url,
                                                fit: BoxFit.contain,
                                                width: 128,
                                                height: 128,
                                                animated: true,
                                                isThumbnail: false,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Встроенные паки GAlMax: всегда первые, с заголовками разделов.
  Widget _buildBundledPack(
    BuildContext context,
    List<BundledStickerPack> packs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/logo/mini/logo_mini.png',
              width: 40,
              height: 40,
            ),
          ),
          title: const Text(
            'GAlMax',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: _uploadingBundled ? const LinearProgressIndicator() : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          dense: true,
        ),
        for (var p = 0; p < packs.length; p++) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(16, p == 0 ? 4 : 12, 16, 4),
            child: Text(
              packs[p].title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              itemCount: packs[p].items.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 84,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (BuildContext context, int index) {
                final sticker = packs[p].items[index];
                return Tooltip(
                  message: sticker.name,
                  child: InkWell(
                    radius: AppConfig.borderRadius,
                    key: ValueKey(sticker.assetPath),
                    onTap: () => _sendBundled(sticker),
                    child: Image.asset(
                      sticker.assetPath,
                      fit: BoxFit.contain,
                      width: 128,
                      height: 128,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
