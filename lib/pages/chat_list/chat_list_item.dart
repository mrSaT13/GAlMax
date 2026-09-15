// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/chat_list/unread_bubble.dart';
import 'package:galmax/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:galmax/utils/room_status_extension.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:galmax/widgets/future_loading_dialog.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

class ChatListItem extends StatelessWidget {
  final Room room;
  final Room? space;
  final bool activeChat;
  final void Function(BuildContext context)? onLongPress;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    required this.onTap,
    this.onLongPress,
    this.onForget,
    this.filter,
    this.space,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isMuted = room.pushRuleState != PushRuleState.notify;
    final typingText = room.getLocalizedTypingText(context);
    final lastEvent = room.lastEvent;
    final ownMessage = lastEvent?.senderId == room.client.userID;
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = directChatMatrixId != null;
    final hasNotifications = room.notificationCount > 0;
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final filter = this.filter;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }

    final needLastEventSender =
        lastEvent != null &&
        room.getState(EventTypes.RoomMember, lastEvent.senderId) == null;
    final space = this.space;
    // Неотправленный черновик (текст + ответ/редактирование) — как в Telegram.
    final draft = Matrix.of(context).store.getString('draft_${room.id}');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.hardEdge,
        // Цвета из темы: захардкоженный darkCard давал зелень
        // при любом выбранном цвете.
        color: activeChat
            ? theme.colorScheme.primaryContainer.withAlpha(120)
            : theme.colorScheme.surfaceContainer.withOpacity(0.85),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: () => onLongPress?.call(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // Avatar with presence dot
                _buildAvatar(
                  context,
                  room: room,
                  space: space,
                  directChatMatrixId: directChatMatrixId,
                  onLongPress: onLongPress,
                ),
                const SizedBox(width: 12),

                // Content area
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + time row
                      Row(
                        children: [
                          if (room.isFavourite)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.push_pin,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              displayname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: room.hasNewMessages
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (!room.isSpace && room.membership != Membership.invite)
                            Text(
                              room.latestEventReceivedTime.localizedTimeShort(
                                context,
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: room.hasNewMessages
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: room.highlightCount >= 1
                                    ? theme.colorScheme.error
                                    : room.hasNewMessages
                                        ? Theme.of(context).colorScheme.primary
                                        : theme.colorScheme.onSurface.withAlpha(150),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Message preview + unread row
                      Row(
                        children: [
                          if (typingText.isEmpty &&
                              ownMessage &&
                              room.lastEvent?.status.isSending == true) ...[
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (typingText.isNotEmpty)
                            Icon(
                              Icons.edit_outlined,
                              color: Theme.of(context).colorScheme.primary,
                              size: 14,
                            ),
                          if (typingText.isNotEmpty) const SizedBox(width: 4),
                          Expanded(
                            child: room.isSpace && room.membership == Membership.join
                                ? Text(
                                    L10n.of(context).countChats(
                                      room.spaceChildren.length,
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.onSurface.withAlpha(150),
                                    ),
                                  )
                                : typingText.isNotEmpty
                                    ? Text(
                                        typingText,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(context).colorScheme.primary,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        maxLines: 1,
                                        softWrap: false,
                                      )
                                    : (draft != null && draft.isNotEmpty)
                                        ? Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: 'Черновик: ',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: draft,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: theme.colorScheme.onSurface
                                                        .withAlpha(150),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            softWrap: false,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        : FutureBuilder(
                                        key: ValueKey(
                                          '${lastEvent?.eventId}_${lastEvent?.type}_${lastEvent?.redacted}',
                                        ),
                                        future: needLastEventSender
                                            ? lastEvent.calcLocalizedBody(
                                                MatrixLocals(L10n.of(context)),
                                                hideReply: true,
                                                hideEdit: true,
                                                plaintextBody: true,
                                                removeMarkdown: true,
                                                withSenderNamePrefix:
                                                    (!isDirectChat ||
                                                    directChatMatrixId !=
                                                        room.lastEvent?.senderId),
                                              )
                                            : null,
                                        initialData: lastEvent?.calcLocalizedBodyFallback(
                                          MatrixLocals(L10n.of(context)),
                                          hideReply: true,
                                          hideEdit: true,
                                          plaintextBody: true,
                                          removeMarkdown: true,
                                          withSenderNamePrefix:
                                              (!isDirectChat ||
                                              directChatMatrixId !=
                                                  room.lastEvent?.senderId),
                                        ),
                                        builder: (context, snapshot) => Text(
                                          room.membership == Membership.invite
                                              ? room
                                                        .getState(
                                                          EventTypes.RoomMember,
                                                          room.client.userID!,
                                                        )
                                                        ?.content
                                                        .tryGet<String>('reason') ??
                                                    (isDirectChat
                                                        ? L10n.of(context).newChatRequest
                                                        : L10n.of(context).inviteGroupChat)
                                              : snapshot.data ??
                                                    L10n.of(context).noMessagesYet,
                                          softWrap: false,
                                          maxLines: room.notificationCount >= 1 ? 2 : 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            decoration: room.lastEvent?.redacted == true
                                                ? TextDecoration.lineThrough
                                                : null,
                                            color: theme.colorScheme.onSurface.withAlpha(
                                              room.hasNewMessages ? 220 : 150,
                                            ),
                                          ),
                                        ),
                                      ),
                          ),
                          const SizedBox(width: 8),

                          // Muted icon
                          if (isMuted)
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurface.withAlpha(100),
                            ),

                          // Unread bubble
                          UnreadBubble(room: room),
                        ],
                      ),
                    ],
                  ),
                ),

                // Invite actions
                if (onForget != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outlined, size: 20),
                    onPressed: onForget,
                    color: theme.colorScheme.error,
                  )
                else if (room.membership == Membership.invite)
                  IconButton(
                    tooltip: L10n.of(context).declineInvitation,
                    icon: const Icon(Icons.delete_forever_outlined, size: 20),
                    color: theme.colorScheme.error,
                    onPressed: () async {
                      final consent = await showOkCancelAlertDialog(
                        context: context,
                        title: L10n.of(context).declineInvitation,
                        message: L10n.of(context).areYouSure,
                        okLabel: L10n.of(context).yes,
                        isDestructive: true,
                      );
                      if (consent != OkCancelResult.ok) return;
                      if (!context.mounted) return;
                      await showFutureLoadingDialog(
                        context: context,
                        future: room.leave,
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

  Widget _buildAvatar(
    BuildContext context, {
    required Room room,
    Room? space,
    String? directChatMatrixId,
    void Function(BuildContext context)? onLongPress,
  }) {
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );

    return GestureDetector(
      onTap: () => onLongPress?.call(context),
      child: SizedBox(
        width: Avatar.defaultSize,
        height: Avatar.defaultSize,
        child: Stack(
          children: [
            if (space != null)
              Positioned(
                top: 0,
                left: 0,
                child: Avatar(
                  shapeBorder: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(
                      AppConfig.spaceBorderRadius * 0.75,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(
                    AppConfig.spaceBorderRadius * 0.75,
                  ),
                  mxContent: space.avatar,
                  size: Avatar.defaultSize * 0.75,
                  name: space.getLocalizedDisplayname(),
                ),
              ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Avatar(
                shapeBorder: space == null
                    ? room.isSpace
                        ? RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(
                              AppConfig.spaceBorderRadius,
                            ),
                          )
                        : null
                    : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          Avatar.defaultSize,
                        ),
                      ),
                borderRadius: room.isSpace
                    ? BorderRadius.circular(AppConfig.spaceBorderRadius)
                    : null,
                mxContent: room.avatar,
                size: space != null
                    ? Avatar.defaultSize * 0.75
                    : Avatar.defaultSize,
                name: displayname,
                presenceUserId: directChatMatrixId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
