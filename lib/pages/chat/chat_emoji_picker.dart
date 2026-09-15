// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/themes.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/chat/gif_picker.dart';
import 'package:galmax/pages/chat/sticker_picker_dialog.dart';
import 'package:galmax/pages/chat/trust_user_key_dialog.dart';
import 'package:galmax/utils/localized_exception_extension.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'chat.dart';

class ChatEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: GalmaxThemes.animationDuration,
      curve: GalmaxThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: controller.showEmojiPicker
          ? MediaQuery.sizeOf(context).height / 2
          : 0,
      child: controller.showEmojiPicker
          ? DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurface.withAlpha(150),
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: [
                      Tab(text: L10n.of(context).emojis),
                      Tab(text: L10n.of(context).stickers),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.gif_box_outlined, size: 18),
                            const SizedBox(width: 4),
                            const Text('GIF'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        EmojiPicker(
                          onEmojiSelected: controller.onEmojiSelected,
                          onBackspacePressed: controller.emojiPickerBackspace,
                          config: Config(
                            locale: Localizations.localeOf(context),
                            emojiViewConfig: EmojiViewConfig(
                              noRecents: const NoRecent(),
                              backgroundColor:
                                  theme.colorScheme.onInverseSurface,
                            ),
                            bottomActionBarConfig: const BottomActionBarConfig(
                              enabled: false,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backspaceColor: Theme.of(context).colorScheme.primary,
                              iconColor: Theme.of(context).colorScheme.primary.withAlpha(128),
                              iconColorSelected: Theme.of(context).colorScheme.primary,
                              indicatorColor: Theme.of(context).colorScheme.primary,
                              backgroundColor: theme.colorScheme.surface,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: Color.lerp(
                                theme.colorScheme.surface,
                                theme.colorScheme.primaryContainer,
                                0.75,
                              )!,
                              indicatorColor: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        StickerPickerDialog(
                          room: controller.room,
                          onSelected: (sticker) async {
                            final proceed = await showTrustUserInRoomDialog(
                              context,
                              controller.room,
                            );
                            if (!proceed) return;
                            try {
                              await controller.room.sendEvent(
                                {
                                  'body': sticker.body,
                                  'info': sticker.info ?? {},
                                  'url': sticker.url.toString(),
                                },
                                type: EventTypes.Sticker,
                                threadRootEventId: controller.activeThreadId,
                                threadLastEventId: controller.threadLastEventId,
                              );
                              controller.hideEmojiPicker();
                            } catch (e, s) {
                              Logs().e('[Sticker] sendEvent failed', e, s);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toLocalizedString(context),
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        GifPicker(
                          onGifSelected: (gifUrl) async {
                            controller.hideEmojiPicker();
                            final proceed = await showTrustUserInRoomDialog(
                              context,
                              controller.room,
                            );
                            if (!proceed) return;
                            try {
                              final client = controller.room.client;
                              final uri = Uri.parse(gifUrl);
                              final response = await client.httpClient.get(uri);
                              if (response.statusCode != 200) return;
                              final bytes = response.bodyBytes;
                              final mxcUri = await client.uploadContent(
                                bytes,
                                filename: 'gif_${DateTime.now().millisecondsSinceEpoch}.gif',
                              );
                              await controller.room.sendEvent(
                                {
                                  'body': 'GIF',
                                  'info': {
                                    'mimetype': 'image/gif',
                                    'w': 200,
                                    'h': 200,
                                    'size': bytes.length,
                                  },
                                  'url': mxcUri.toString(),
                                  'msgtype': 'm.image',
                                },
                                threadRootEventId: controller.activeThreadId,
                                threadLastEventId: controller.threadLastEventId,
                              );
                            } catch (e, s) {
                              Logs().e('[GIF] send failed $gifUrl', e, s);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toLocalizedString(context),
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class NoRecent extends StatelessWidget {
  const NoRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
