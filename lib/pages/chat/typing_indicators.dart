// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/themes.dart';
import 'package:galmax/pages/chat/chat.dart';
import 'package:galmax/utils/galmax_activity.dart';
import 'package:galmax/widgets/avatar.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class TypingIndicators extends StatelessWidget {
  final ChatController controller;
  const TypingIndicators(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const avatarSize = Avatar.defaultSize / 2;

    final client = Matrix.of(context).client;
    GalmaxActivityStore.watch(client);
    final activityStore = GalmaxActivityStore.of(client);

    return StreamBuilder<Object>(
      stream: client.onSync.stream.where(
        (syncUpdate) =>
            syncUpdate.rooms?.join?[controller.room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.typing',
            ) ??
            false,
      ),
      builder: (context, _) {
        // Копия: сам список из SDK не мутируем. Себя из печатающих
        // убираем — «печатает…» про себя не показываем.
        final typingUsers = controller.room.typingUsers
            .where((u) => u.stateKey != Matrix.of(context).client.userID)
            .toList();

        return StreamBuilder(
          stream: activityStore.changed,
          builder: (context, _) {
            // activitiesIn может вернуть константный пустой map —
            // копируем, иначе remove() кинет UnsupportedError и в релизе
            // вместо индикатора будет серая плашка.
            final activities =
                Map.of(activityStore.activitiesIn(controller.room.id));
            activities.remove(client.userID);
            final activityEntry = activities.entries.firstOrNull;
            final showActivity =
                activityEntry != null && typingUsers.isEmpty;
            if (typingUsers.isEmpty && !showActivity) {
              return const SizedBox.shrink();
            }
            return _buildBubble(
              context,
              theme,
              avatarSize,
              typingUsers,
              activityText: showActivity
                  ? GalmaxActivity.labelFor(activityEntry.value)
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildBubble(
    BuildContext context,
    ThemeData theme,
    double avatarSize,
    List<User> typingUsers, {
    String? activityText,
  }) {
    final hasContent = typingUsers.isNotEmpty || activityText != null;
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      child: AnimatedContainer(
        constraints: const BoxConstraints(
          maxWidth: GalmaxThemes.maxTimelineWidth,
        ),
        height: hasContent ? null : 0,
        duration: GalmaxThemes.animationDuration,
        curve: GalmaxThemes.animationCurve,
        alignment:
            controller.timeline?.events.isNotEmpty == true &&
                controller.timeline!.events.first.senderId ==
                    Matrix.of(context).client.userID
            ? Alignment.topRight
            : Alignment.topLeft,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: hasContent
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    alignment: Alignment.center,
                    height: avatarSize,
                    width: Avatar.defaultSize,
                    child: Stack(
                      children: [
                        if (typingUsers.isNotEmpty)
                          Avatar(
                            size: avatarSize,
                            mxContent: typingUsers.first.avatarUrl,
                            name: typingUsers.first.calcDisplayname(),
                          )
                        else
                          Container(
                            width: avatarSize,
                            height: avatarSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primary,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.mic,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        if (typingUsers.length == 2)
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Avatar(
                              size: avatarSize,
                              mxContent: typingUsers.length == 2
                                  ? typingUsers.last.avatarUrl
                                  : null,
                              name: typingUsers.length == 2
                                  ? typingUsers.last.calcDisplayname()
                                  : '+${typingUsers.length - 1}',
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppConfig.borderRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _TypingDots(),
                          if (activityText != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              activityText,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => __TypingDotsState();
}

class __TypingDotsState extends State<_TypingDots> {
  int _tick = 0;

  late final Timer _timer;

  static const Duration animationDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    _timer = Timer.periodic(animationDuration, (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tick = (_tick + 1) % 4;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 8.0;

    return Row(
      mainAxisSize: .min,
      children: [
        for (var i = 1; i <= 3; i++)
          AnimatedContainer(
            duration: animationDuration * 1.5,
            curve: GalmaxThemes.animationCurve,
            width: size,
            height: _tick == i ? size * 2 : size,
            margin: EdgeInsets.symmetric(
              horizontal: 2,
              vertical: _tick == i ? 4 : 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 2),
              color: theme.colorScheme.secondary,
            ),
          ),
      ],
    );
  }
}
