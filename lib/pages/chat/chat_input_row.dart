// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/chat/recording_input_row.dart';
import 'package:galmax/pages/chat/recording_view_model.dart';
import 'package:galmax/utils/other_party_can_receive.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/widgets/avatar.dart';
import 'package:galmax/widgets/hover_builder.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import 'chat.dart';
import 'input_bar.dart';
import 'link_preview_bar.dart';

class ChatInputRow extends StatefulWidget {
  final ChatController controller;

  static const double height = 56.0;

  const ChatInputRow(this.controller, {super.key});

  @override
  State<ChatInputRow> createState() => _ChatInputRowState();
}

class _ChatInputRowState extends State<ChatInputRow> {
  bool _isVideoMode = false;
  bool _linkPreviewDismissed = false;
  String? _lastPreviewText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = widget.controller;
    final textMessageOnly =
        controller.sendController.text.isNotEmpty ||
        controller.replyEvent != null ||
        controller.editEvent != null;

    if (!controller.room.otherPartyCanReceiveMessages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RecordingViewModel(
      builder: (context, recordingViewModel) {
        if (recordingViewModel.isRecording) {
          return RecordingInputRow(
            state: recordingViewModel,
            onSend: controller.onVoiceMessageSend,
          );
        }

        // Select mode
        if (controller.selectMode) {
          return _buildSelectMode(context, controller, theme);
        }

        // Normal input mode
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            // Цвета только из темы: захардкоженные AppConfig.darkBackground /
            // darkCard ломали кастомные сиды и dynamic color в тёмной теме.
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLinkPreview(controller),
                // Очередь отложенных: тап — список/отмена.
                if (controller.scheduledMessages.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: ActionChip(
                        avatar: const Icon(Icons.schedule_outlined, size: 16),
                        label: Text(
                          'Отложено: ${controller.scheduledMessages.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: controller.showScheduledList,
                      ),
                    ),
                  ),
                Row(
                  // Кнопки по центру строки: при высокой поле ввода
                  // они не должны «съезжать» вниз.
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                // Attachment button (+)
                _buildIconButton(
                  icon: Icons.add_circle_outline,
                  onTap: () => _showAttachmentMenu(context, controller, theme),
                  isDark: isDark,
                ),

                // Emoji button
                _buildIconButton(
                  icon: controller.showEmojiPicker
                      ? Icons.keyboard
                      : Icons.add_reaction_outlined,
                  onTap: controller.emojiPickerAction,
                  isDark: isDark,
                ),

                // Text input field
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                        80,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: InputBar(
                      room: controller.room,
                      minLines: 1,
                      maxLines: 8,
                      autofocus: !PlatformInfos.isMobile,
                      keyboardType: TextInputType.multiline,
                      textInputAction:
                          AppSettings.sendOnEnter.value == true &&
                              PlatformInfos.isMobile
                          ? TextInputAction.send
                          : null,
                      onSubmitted: controller.onInputBarSubmitted,
                      onSubmitImage: controller.sendImageFromClipBoard,
                      focusNode: controller.inputFocus,
                      controller: controller.sendController,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        counter: const SizedBox.shrink(),
                        hintText: controller.room.encrypted
                            ? L10n.of(context).encryptedMessage
                            : L10n.of(context).unencryptedMessage,
                        hintMaxLines: 1,
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onSurface.withAlpha(100),
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        filled: false,
                      ),
                      onChanged: (text) {
                        setState(() {});
                        controller.onInputBarChanged(text);
                      },
                      suggestionEmojis:
                          getDefaultEmojiLocale(
                            AppSettings.emojiSuggestionLocale.value.isNotEmpty
                                ? Locale(
                                    AppSettings.emojiSuggestionLocale.value,
                                  )
                                : Localizations.localeOf(context),
                          ).fold(
                            [],
                            (emojis, category) =>
                                emojis..addAll(category.emoji),
                          ),
                    ),
                  ),
                ),

                // Mic / Video / Send button (the key toggle feature)
                _buildMicVideoSendButton(
                  context,
                  controller: controller,
                  recordingViewModel: recordingViewModel,
                  hasText: textMessageOnly,
                  isDark: isDark,
                  theme: theme,
                ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Предпросмотр первой ссылки из черновика/ввода. Скрывается крестиком
  /// до смены текста.
  Widget _buildLinkPreview(ChatController controller) {
    final text = controller.sendController.text;
    if (text != _lastPreviewText) {
      _lastPreviewText = text;
      _linkPreviewDismissed = false;
    }
    if (_linkPreviewDismissed || text.isEmpty) {
      return const SizedBox.shrink();
    }
    final url = extractFirstLink(text);
    if (url == null) return const SizedBox.shrink();
    return LinkPreviewBar(
      url: url,
      onClose: () => setState(() => _linkPreviewDismissed = true),
    );
  }

  Widget _buildMicVideoSendButton(
    BuildContext context, {
    required ChatController controller,
    required RecordingViewModelState recordingViewModel,
    required bool hasText,
    required bool isDark,
    required ThemeData theme,
  }) {
    // If text is entered → show send button
    if (hasText) {
      return Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.only(left: 4),
        child: Material(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: controller.send,
            // Долгое нажатие — запланировать отправку на время.
            onLongPress: controller.scheduleMessage,
            child: const Icon(
              Icons.send_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      );
    }

    // If no text → show mic/video toggle
    return Container(
      width: 48,
      height: 48,
      margin: const EdgeInsets.only(left: 4),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            if (PlatformInfos.platformCanRecord) {
              // Toggle between mic and video mode
              setState(() {
                _isVideoMode = !_isVideoMode;
              });
              // Start recording with the selected mode
              recordingViewModel.startRecording(controller.room);
            }
          },
          onLongPress: () {
            if (PlatformInfos.platformCanRecord) {
              recordingViewModel.startRecording(controller.room);
            }
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _isVideoMode ? Icons.videocam : Icons.mic,
              key: ValueKey(_isVideoMode),
              color: Theme.of(context).colorScheme.primary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectMode(
    BuildContext context,
    ChatController controller,
    ThemeData theme,
  ) {
    final selectedTextButtonStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onTertiaryContainer,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (controller.selectedEvents.every(
            (event) => event.status == EventStatus.error,
          ))
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: controller.deleteErrorEventsAction,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.delete_forever_outlined),
                  Text(L10n.of(context).delete),
                ],
              ),
            )
          else
            TextButton(
              style: selectedTextButtonStyle,
              onPressed: controller.forwardEventsAction,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.keyboard_arrow_left_outlined),
                  Text(L10n.of(context).forward),
                ],
              ),
            ),
          if (controller.selectedEvents.length == 1)
            controller.selectedEvents.first
                      .getDisplayEvent(controller.timeline!)
                      .status
                      .isSent
                ? TextButton(
                    style: selectedTextButtonStyle,
                    onPressed: controller.replyAction,
                    child: Row(
                      children: <Widget>[
                        Text(L10n.of(context).reply),
                        const Icon(Icons.keyboard_arrow_right),
                      ],
                    ),
                  )
                : TextButton(
                    style: selectedTextButtonStyle,
                    onPressed: controller.sendAgainAction,
                    child: Row(
                      children: <Widget>[
                        Text(L10n.of(context).tryToSendAgain),
                        const SizedBox(width: 4),
                        const Icon(Icons.send_outlined, size: 16),
                      ],
                    ),
                  ),
        ],
      ),
    );
  }

  void _showAttachmentMenu(
    BuildContext context,
    ChatController controller,
    ThemeData theme,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withAlpha(50),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _buildAttachmentOption(
                  context,
                  icon: Icons.gps_fixed_outlined,
                  label: L10n.of(context).shareLocation,
                  onTap: () {
                    Navigator.pop(context);
                    controller.onAddPopupMenuButtonSelected(
                      AddPopupMenuActions.location,
                    );
                  },
                ),
                _buildAttachmentOption(
                  context,
                  icon: Icons.poll_outlined,
                  label: L10n.of(context).startPoll,
                  onTap: () {
                    Navigator.pop(context);
                    controller.onAddPopupMenuButtonSelected(
                      AddPopupMenuActions.poll,
                    );
                  },
                ),
                if (PlatformInfos.isMobile) ...[
                  _buildAttachmentOption(
                    context,
                    icon: Icons.videocam_outlined,
                    label: L10n.of(context).recordAVideo,
                    onTap: () {
                      Navigator.pop(context);
                      controller.onAddPopupMenuButtonSelected(
                        AddPopupMenuActions.videoCamera,
                      );
                    },
                  ),
                  _buildAttachmentOption(
                    context,
                    icon: Icons.fiber_smart_record,
                    label: L10n.of(context).roundVideo,
                    onTap: () {
                      Navigator.pop(context);
                      controller.onAddPopupMenuButtonSelected(
                        AddPopupMenuActions.roundVideo,
                      );
                    },
                  ),
                  _buildAttachmentOption(
                    context,
                    icon: Icons.camera_alt_outlined,
                    label: L10n.of(context).takeAPhoto,
                    onTap: () {
                      Navigator.pop(context);
                      controller.onAddPopupMenuButtonSelected(
                        AddPopupMenuActions.photoCamera,
                      );
                    },
                  ),
                ],
                _buildAttachmentOption(
                  context,
                  icon: Icons.photo_outlined,
                  label: L10n.of(context).sendImage,
                  onTap: () {
                    Navigator.pop(context);
                    controller.onAddPopupMenuButtonSelected(
                      AddPopupMenuActions.image,
                    );
                  },
                ),
                _buildAttachmentOption(
                  context,
                  icon: Icons.video_camera_back_outlined,
                  label: L10n.of(context).sendVideo,
                  onTap: () {
                    Navigator.pop(context);
                    controller.onAddPopupMenuButtonSelected(
                      AddPopupMenuActions.video,
                    );
                  },
                ),
                _buildAttachmentOption(
                  context,
                  icon: Icons.attachment_outlined,
                  label: L10n.of(context).sendFile,
                  onTap: () {
                    Navigator.pop(context);
                    controller.onAddPopupMenuButtonSelected(
                      AddPopupMenuActions.file,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(30),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 15,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }
}
