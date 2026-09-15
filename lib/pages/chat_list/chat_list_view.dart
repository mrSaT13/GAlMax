// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/config/themes.dart';
import 'package:galmax/pages/chat_list/chat_list.dart';
import 'package:galmax/pages/chat_list/navigation_rail.dart';
import 'package:galmax/pages/chat_list/start_chat_fab.dart';
import 'package:galmax/widgets/app_background.dart';
import 'package:galmax/widgets/mini_player.dart';
import 'package:flutter/material.dart';

import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final oneColumnSpacesMode =
        !GalmaxThemes.isColumnMode(context) &&
        AppSettings.displayNavigationRail.value;
    return PopScope(
      canPop: !controller.isSearchMode && controller.activeSpaceId == null,
      onPopInvokedWithResult: (pop, _) {
        if (pop) return;
        if (controller.activeSpaceId != null) {
          controller.clearActiveSpace();
          return;
        }
        if (controller.isSearchMode) {
          controller.cancelSearch();
          return;
        }
      },
      child: Row(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: AnimatedSize(
              duration: GalmaxThemes.animationDuration,
              curve: GalmaxThemes.animationCurve,
              child:
                  (GalmaxThemes.isColumnMode(context) ||
                      AppSettings.displayNavigationRail.value)
                  ? SpacesNavigationRail(
                      activeSpaceId: controller.activeSpaceId,
                      onGoToChats: controller.clearActiveSpace,
                      onGoToSpaceId: controller.setActiveSpace,
                    )
                  : SizedBox(
                      width: 0,
                      height: MediaQuery.sizeOf(context).height,
                    ),
            ),
          ),
          if (GalmaxThemes.isColumnMode(context) ||
              AppSettings.displayNavigationRail.value)
            if (GalmaxThemes.isColumnMode(context))
              Container(width: 1, color: Theme.of(context).dividerColor),

          Expanded(
            child: GestureDetector(
              onTap: FocusManager.instance.primaryFocus?.unfocus,
              excludeFromSemantics: true,
              behavior: HitTestBehavior.translucent,
              child: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.05),
                                  Theme.of(context).colorScheme.surface,
                                  Theme.of(context).colorScheme.surface,
                                ],
                                stops: const [0.0, 0.3, 1.0],
                              ),
                            ),
                          ),
                          const AppBackground(),
                          SafeArea(
                            // Всегда учитываем статус-бар: иначе поиск
                            // уезжает под системные иконки (см. скриншот).
                            top: true,
                            bottom: false,
                            left: false,
                            right: false,
                            child: Material(
                              clipBehavior: oneColumnSpacesMode
                                  ? Clip.hardEdge
                                  : Clip.none,
                              borderRadius: oneColumnSpacesMode
                                  ? BorderRadius.only(
                                      topLeft: Radius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                    )
                                  : null,
                              color: Colors.transparent,
                              child: ChatListViewBody(controller),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Persistent mini-player for audio/video messages
                    const MiniPlayer(),
                  ],
                ),
                floatingActionButton:
                    !controller.isSearchMode &&
                        controller.activeSpaceId == null &&
                        !GalmaxThemes.isColumnMode(context)
                    ? ValueListenableBuilder(
                        valueListenable: controller.scrolledToTop,
                        builder: (context, scrolledToTop, _) => StartChatFab(
                          extended:
                              scrolledToTop &&
                              !AppSettings.displayNavigationRail.value,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
