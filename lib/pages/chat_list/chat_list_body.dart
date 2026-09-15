// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/chat_list/chat_list.dart';
import 'package:galmax/pages/chat_list/chat_list_item.dart';
import 'package:galmax/pages/chat_list/dummy_chat_list_item.dart';
import 'package:galmax/pages/chat_list/search_title.dart';
import 'package:galmax/pages/chat_list/space_view.dart';
import 'package:galmax/utils/favorites_helper.dart';
import 'package:galmax/utils/localized_exception_extension.dart';
import 'package:galmax/utils/stream_extension.dart';
import 'package:galmax/widgets/future_loading_dialog.dart';
import 'package:galmax/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:galmax/widgets/avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';
import '../../widgets/matrix.dart';
import 'chat_list_header.dart';

class ChatListViewBody extends StatefulWidget {
  final ChatListController controller;

  const ChatListViewBody(this.controller, {super.key});

  @override
  State<ChatListViewBody> createState() => _ChatListViewBodyState();
}

class _ChatListViewBodyState extends State<ChatListViewBody> {
  static const _filterOrder = [
    ActiveFilter.allChats,
    ActiveFilter.unread,
    ActiveFilter.groups,
    ActiveFilter.messages,
  ];

  void _onTagSelected(String tag) {
    widget.controller.setActiveFilter(ActiveFilter.tag, tag);
    setState(() {});
  }

  /// Telegram-style swipe: fling left/right anywhere on the list switches tabs.
  void _onHorizontalFling(DragEndDetails details) {
    final controller = widget.controller;
    if (controller.isSearchMode) return;
    if (controller.activeSpaceId != null) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 200) return;
    final currentFilter = controller.activeFilter;
    // Don't handle swipe for tag filters.
    if (currentFilter == ActiveFilter.tag) return;
    final currentIndex = _filterOrder.indexOf(currentFilter);
    if (currentIndex < 0) return;
    if (velocity > 0 && currentIndex > 0) {
      controller.setActiveFilter(_filterOrder[currentIndex - 1], null);
    } else if (velocity < 0 && currentIndex < _filterOrder.length - 1) {
      controller.setActiveFilter(_filterOrder[currentIndex + 1], null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    final activeSpace = controller.activeSpaceId;
    if (activeSpace != null) {
      return SpaceView(
        key: ValueKey(activeSpace),
        spaceId: activeSpace,
        onBack: controller.clearActiveSpace,
        onChatTab: controller.onChatTap,
        activeChat: controller.activeChat,
      );
    }
    final spaces = client.rooms.where((r) => r.isSpace);
    final spaceDelegateCandidates = <String, Room>{};
    for (final space in spaces) {
      for (final spaceChild in space.spaceChildren) {
        final roomId = spaceChild.roomId;
        if (roomId == null) continue;
        spaceDelegateCandidates[roomId] = space;
      }
    }

    final publicRooms = controller.roomSearchResult?.chunk
        .where((room) => room.roomType != 'm.space')
        .toList();
    final publicSpaces = controller.roomSearchResult?.chunk
        .where((room) => room.roomType == 'm.space')
        .toList();
    final userSearchResult = controller.userSearchResult;
    const dummyChatCount = 4;
    final filter = controller.searchController.text.toLowerCase();
    return StreamBuilder(
      key: ValueKey(client.userID.toString()),
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final rooms = controller.filteredRooms
            .where(
              (room) =>
                  (!AppSettings.hideRoomsInSpaces.value ||
                      spaceDelegateCandidates[room.id] == null) &&
                  !FavoritesHelper.isSelfRoom(room),
            )
            .toList();
        // Unfiltered rooms for per-tab unread badges.
        // Комната «Избранное» с собой исключена: вход один —
        // закреплённая плитка, иначе Избранное двоится в списке.
        final allRooms = client.rooms
            .where(
              (room) =>
                  (!AppSettings.hideRoomsInSpaces.value ||
                      spaceDelegateCandidates[room.id] == null) &&
                  !FavoritesHelper.isSelfRoom(room),
            )
            .toList();

        return GestureDetector(
          onHorizontalDragEnd: _onHorizontalFling,
          child: CustomScrollView(
            controller: controller.scrollController,
            slivers: [
            ChatListHeader(controller: controller),
            // Telegram-порядок: табы СРАЗУ под поиском и закреплены (pinned),
            // empty-стейт — НИЖЕ табов. Раньше empty рисовался до табов,
            // поэтому при пустых "Непрочитанных" пилюля съезжала вниз
            // и болталась под картинкой вместо закрепления сверху.
            // Telegram-style tab bar: own sliver (pinned), never nested
            // inside SliverList — slivers can't be box children.
            if (client.rooms.isNotEmpty && !controller.isSearchMode)
              SliverPersistentHeader(
                pinned: true,
                delegate: _FilterBarDelegate(
                  activeFilter: controller.activeFilter,
                  activeTag: controller.activeTag,
                  unreadCounts: {
                    for (final f in _filterOrder)
                      f: allRooms
                          .where(
                            controller.getRoomFilterByActiveFilter(f),
                          )
                          .where((r) => r.isUnreadOrInvited)
                          .length,
                  },
                  tags: controller.roomTags,
                  onFilter: (f) => controller.setActiveFilter(f, null),
                  onTag: _onTagSelected,
                ),
              ),
            SliverList(
              delegate: SliverChildListDelegate([
                // Избранное — закрепом под табами, видно что это и где лежит.
                // Комната с собой скрыта из общего списка
                // (см. FavoritesHelper.isSelfRoom), поэтому плитка —
                // единственный вход. Тумблер «Показывать Избранное»
                // убирает её совсем. В режиме поиска показываем её, только
                // если запрос похож на «избранное», иначе поиск по слову
                // «избранное» давал бы пусто.
                if (AppSettings.showFavoritesTile.value &&
                    _showFavoritesTile(controller.isSearchMode, filter))
                  const _FavoritesTile(),
                if (controller.isSearchMode) ...[
                  SearchTitle(
                    title: L10n.of(context).publicRooms,
                    icon: const Icon(Icons.explore_outlined),
                  ),
                  PublicRoomsHorizontalList(publicRooms: publicRooms),
                  SearchTitle(
                    title: L10n.of(context).publicSpaces,
                    icon: const Icon(Icons.workspaces_outlined),
                  ),
                  PublicRoomsHorizontalList(publicRooms: publicSpaces),
                  SearchTitle(
                    title: L10n.of(context).users,
                    icon: const Icon(Icons.group_outlined),
                  ),
                  AnimatedContainer(
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    height:
                        userSearchResult == null ||
                            userSearchResult.results.isEmpty
                        ? 0
                        : 106,
                    duration: GalmaxThemes.animationDuration,
                    curve: GalmaxThemes.animationCurve,
                    child: userSearchResult == null
                        ? null
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: userSearchResult.results.length,
                            itemBuilder: (context, i) => _SearchItem(
                              title:
                                  userSearchResult.results[i].displayName ??
                                  userSearchResult
                                      .results[i]
                                      .userId
                                      .localpart ??
                                  L10n.of(context).unknownDevice,
                              avatar: userSearchResult.results[i].avatarUrl,
                              onPressed: () => UserDialog.show(
                                context: context,
                                profile: userSearchResult.results[i],
                              ),
                            ),
                          ),
                  ),
                ],
                if (controller.isSearchMode)
                  SearchTitle(
                    title: L10n.of(context).chats,
                    icon: const Icon(Icons.forum_outlined),
                  ),
              ]),
            ),
            // Пустой фильтр: SliverFillRemaining центрирует по оставшемуся
            // экрану ПОД табами, а не толкает табы вниз.
            if (client.prevBatch != null &&
                rooms.isEmpty &&
                !controller.isSearchMode)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: .center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        const Column(
                          mainAxisSize: .min,
                          children: [
                            DummyChatListItem(opacity: 0.5, animate: false),
                            DummyChatListItem(opacity: 0.3, animate: false),
                          ],
                        ),
                        Icon(
                          CupertinoIcons.chat_bubble_text_fill,
                          size: 128,
                          color: theme.colorScheme.secondary,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        client.rooms.isEmpty
                            ? L10n.of(context).noChatsFoundHere
                            : L10n.of(context).noMoreChatsFound,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (client.prevBatch == null)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => DummyChatListItem(
                    opacity: (dummyChatCount - i) / dummyChatCount,
                    animate: true,
                  ),
                  childCount: dummyChatCount,
                ),
              ),
            if (client.prevBatch != null)
              SliverSafeArea(
                top: false,
                sliver: SliverList.builder(
                  itemCount: rooms.length,
                  itemBuilder: (BuildContext context, int i) {
                    final room = rooms[i];
                    final space = spaceDelegateCandidates[room.id];
                    return ChatListItem(
                      room,
                      space: space,
                      key: Key('chat_list_item_${room.id}'),
                      filter: filter,
                      onTap: () => controller.onChatTap(room),
                      onLongPress: (context) =>
                          controller.chatContextAction(room, context, space),
                    activeChat: controller.activeChat == room.id,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
    );
  }
}

/// Telegram-style single-block tab bar, pinned on top of the chat list.
/// Tap switches filter, fling left/right on the list does the same.
class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final ActiveFilter activeFilter;
  final String? activeTag;
  final Map<ActiveFilter, int> unreadCounts;
  final Map<String, int> tags;
  final void Function(ActiveFilter) onFilter;
  final void Function(String) onTag;

  static const _order = [
    ActiveFilter.allChats,
    ActiveFilter.unread,
    ActiveFilter.groups,
    ActiveFilter.messages,
  ];

  // Ширины сегментов (флексы): «Непрочитанные» и «Сообщения» длиннее,
  // им больше места — тогда весь текст одного размера (12sp) и ничего
  // не ужимается/не обрезается только в одной вкладке.
  static const _flex = [8, 13, 8, 10];
  static const _totalFlex = 39;

  double _segLeft(double width, int index) {
    var sum = 0;
    for (var i = 0; i < index; i++) {
      sum += _flex[i];
    }
    return width * sum / _totalFlex;
  }

  double _segWidth(double width, int index) =>
      width * _flex[index] / _totalFlex;

  const _FilterBarDelegate({
    required this.activeFilter,
    required this.activeTag,
    required this.unreadCounts,
    required this.tags,
    required this.onFilter,
    required this.onTag,
  });

  bool get _hasTags => tags.isNotEmpty;

  @override
  double get minExtent => _hasTags ? 100 : 56;

  @override
  double get maxExtent => _hasTags ? 100 : 56;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedIndex = activeFilter == ActiveFilter.tag
        ? -1
        : _order.indexOf(activeFilter);
    // Frosted glass: блюр под таб-баром, чтобы список не просвечивал текстом.
    // Внешний фон прозрачный (блюр + фон экрана), сама пилюля — мягкая,
    // полупрозрачная, без жёсткого «серого прямоугольника».
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.5),
                width: 0.5,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Stack(
                  children: [
                    if (selectedIndex >= 0)
                      AnimatedPositioned(
                        duration: GalmaxThemes.animationDuration,
                        curve: GalmaxThemes.animationCurve,
                        left: _segLeft(width, selectedIndex) + 2,
                        top: 2,
                        bottom: 2,
                        width: _segWidth(width, selectedIndex) - 4,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            // Капсула под высоту пилюли (40-4=36), а не
                            // прямоугольник: внешняя пилюля круглая (r=20).
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withAlpha(80),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < _order.length; i++)
                          SizedBox(
                            width: _segWidth(width, i),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onFilter(_order[i]),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Flexible(
                                      // Страховка на узких экранах/длинных
                                      // локалях; при нормальных ширинах все
                                      // вкладки идут одним кеглем 12.
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _order[i].toLocalizedString(context),
                                          maxLines: 1,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.2,
                                            fontWeight: FontWeight.w600,
                                            color: i == selectedIndex
                                                ? colorScheme.onPrimary
                                                : colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if ((unreadCounts[_order[i]] ?? 0) > 0)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: i == selectedIndex
                                              ? colorScheme.onPrimary
                                                  .withAlpha(45)
                                              : colorScheme.primary,
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          '${unreadCounts[_order[i]]}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: i == selectedIndex
                                                ? colorScheme.onPrimary
                                                : colorScheme.onPrimary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          if (_hasTags)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final entry in tags.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 8),
                      child: FilterChip(
                        selected: entry.key == activeTag,
                        onSelected: (_) => onTag(entry.key),
                        label: Text(entry.key.replaceFirst('u.', '')),
                      ),
                    ),
                ],
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _FilterBarDelegate oldDelegate) =>
      oldDelegate.activeFilter != activeFilter ||
      oldDelegate.activeTag != activeTag ||
      oldDelegate.unreadCounts != unreadCounts ||
      oldDelegate.tags != tags;
}

class PublicRoomsHorizontalList extends StatelessWidget {
  const PublicRoomsHorizontalList({super.key, required this.publicRooms});

  final List<PublishedRoomsChunk>? publicRooms;

  @override
  Widget build(BuildContext context) {
    final publicRooms = this.publicRooms;
    return AnimatedContainer(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: publicRooms == null || publicRooms.isEmpty ? 0 : 106,
      duration: GalmaxThemes.animationDuration,
      curve: GalmaxThemes.animationCurve,
      child: publicRooms == null
          ? null
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: publicRooms.length,
              itemBuilder: (context, i) => _SearchItem(
                title:
                    publicRooms[i].name ??
                    publicRooms[i].canonicalAlias?.localpart ??
                    L10n.of(context).group,
                avatar: publicRooms[i].avatarUrl,
                onPressed: () => showAdaptiveDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (c) => PublicRoomDialog(
                    roomAlias:
                        publicRooms[i].canonicalAlias ?? publicRooms[i].roomId,
                    chunk: publicRooms[i],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SearchItem extends StatelessWidget {
  final String title;
  final Uri? avatar;
  final void Function() onPressed;

  const _SearchItem({
    required this.title,
    this.avatar,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    child: SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: .min,
        children: [
          const SizedBox(height: 8),
          Avatar(mxContent: avatar, name: title),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

/// В режиме поиска плитка видна при пустом запросе или когда запрос
/// похож на «избранное» — иначе её не найти через поиск, а комната-дубль
/// из списка скрыта.
bool _showFavoritesTile(bool isSearchMode, String filter) {
  if (!isSearchMode) return true;
  final q = filter.trim().toLowerCase();
  if (q.isEmpty) return true;
  return 'избранное'.contains(q) ||
      'favorites'.contains(q) ||
      'favourite'.contains(q) ||
      'сохранённые'.contains(q) ||
      'сохраненные'.contains(q) ||
      'заметки'.contains(q);
}

/// Избранное как в Telegram — закреплённая плитка над списком чатов.
/// Звёздочка + подпись где лежит, чтобы было понятно что это.
class _FavoritesTile extends StatelessWidget {
  const _FavoritesTile();

  Future<void> _open(BuildContext context) async {
    final client = Matrix.of(context).client;
    if (FavoritesHelper.mode == FavoritesHelper.modeLocal) {
      if (context.mounted) context.go('/rooms/favorites');
      return;
    }
    final res = await showFutureLoadingDialog(
      context: context,
      future: () => FavoritesHelper.ensureSelfRoom(client),
    );
    if (res.error != null || !context.mounted) return;
    context.go('/rooms/${res.result}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocal = FavoritesHelper.mode == FavoritesHelper.modeLocal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        color: theme.colorScheme.primaryContainer.withAlpha(70),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.star,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Избранное',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        isLocal
                            ? 'Только на этом устройстве'
                            : 'Комната с собой • синхронизируется',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withAlpha(120),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
