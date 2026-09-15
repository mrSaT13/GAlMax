// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/config/themes.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/chat/chat_view.dart';
import 'package:galmax/pages/chat/event_info_dialog.dart';
import 'package:galmax/pages/chat/round_video_recorder.dart';
import 'package:galmax/pages/chat/start_poll_bottom_sheet.dart';
import 'package:galmax/pages/chat/trust_user_key_dialog.dart';
import 'package:galmax/pages/chat/utils/web_file_to_x_file.dart';
import 'package:galmax/pages/chat_details/chat_details.dart';
import 'package:galmax/utils/adaptive_bottom_sheet.dart';
import 'package:galmax/utils/contacts_helper.dart';
import 'package:galmax/utils/error_reporter.dart';
import 'package:galmax/utils/file_selector.dart';
import 'package:galmax/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:galmax/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:galmax/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:galmax/utils/other_party_can_receive.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/utils/show_scaffold_dialog.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:galmax/widgets/future_loading_dialog.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:galmax/widgets/mxc_image.dart';
import 'package:galmax/widgets/share_scaffold_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:universal_html/universal_html.dart' as web;

import '../../utils/account_bundles.dart';
import '../../utils/galmax_activity.dart';
import '../../utils/localized_exception_extension.dart';
import 'send_file_dialog.dart';
import 'scheduled_messages.dart';
import 'send_location_dialog.dart';
import '../../utils/timeline_mutex.dart';

class ChatPage extends StatelessWidget {
  final String roomId;
  final List<ShareItem>? shareItems;
  final String? eventId;

  const ChatPage({
    super.key,
    required this.roomId,
    this.eventId,
    this.shareItems,
  });

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return ChatPageWithRoom(
      key: Key('chat_page_${roomId}_$eventId'),
      room: room,
      shareItems: shareItems,
      eventId: eventId,
    );
  }
}

class ChatPageWithRoom extends StatefulWidget {
  final Room room;
  final List<ShareItem>? shareItems;
  final String? eventId;

  const ChatPageWithRoom({
    super.key,
    required this.room,
    this.shareItems,
    this.eventId,
  });

  @override
  ChatController createState() => ChatController();
}

class ChatController extends State<ChatPageWithRoom>
    with WidgetsBindingObserver {
  Room get room => sendingClient.getRoomById(roomId) ?? widget.room;

  late Client sendingClient;

  Timeline? timeline;

  String? activeThreadId;

  late final Set<String> bigEmojis;

  late final String readMarkerEventId;

  String get roomId => widget.room.id;

  final AutoScrollController scrollController = AutoScrollController();

  late final FocusNode inputFocus;

  Timer? typingCoolDown;
  Timer? typingTimeout;
  bool currentlyTyping = false;
  bool dragging = false;

  final GlobalKey inputBarKey = GlobalKey();

  void onDragEntered(_) => setState(() => dragging = true);

  void onDragExited(_) => setState(() => dragging = false);

  Future<void> onDragDone(DropDoneDetails details) async {
    setState(() => dragging = false);
    if (details.files.isEmpty) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: details.files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  bool get canSaveSelectedEvent =>
      selectedEvents.length == 1 &&
      {
        MessageTypes.Video,
        MessageTypes.Image,
        MessageTypes.Sticker,
        MessageTypes.Audio,
        MessageTypes.File,
      }.contains(selectedEvents.single.messageType);

  void saveSelectedEvent(BuildContext context) =>
      selectedEvents.single.saveFile(context);

  List<Event> selectedEvents = [];

  final Set<String> unfolded = {};

  Event? replyEvent;

  Event? editEvent;

  bool _scrolledUp = false;

  bool get showScrollDownButton =>
      _scrolledUp || timeline?.allowNewEvent == false;

  bool get selectMode => selectedEvents.isNotEmpty;

  final int _loadHistoryCount = 100;

  String pendingText = '';

  bool showEmojiPicker = false;

  String? get threadLastEventId {
    final threadId = activeThreadId;
    if (threadId == null) return null;
    return timeline?.events
        .filterByVisibleInGui(threadId: threadId)
        .firstOrNull
        ?.eventId;
  }

  void enterThread(String eventId) => setState(() {
    activeThreadId = eventId;
    selectedEvents.clear();
  });

  void closeThread() => setState(() {
    activeThreadId = null;
    selectedEvents.clear();
  });

  Future<void> recreateChat() async {
    final room = this.room;
    final userId = room.directChatMatrixID;
    if (userId == null) {
      throw Exception(
        'Try to recreate a room with is not a DM room. This should not be possible from the UI!',
      );
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => room.invite(userId),
    );
  }

  Future<void> leaveChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (!mounted) return;
    if (success.error != null) return;
    context.go('/rooms');
  }

  Future<void> requestHistory([_]) async {
    Logs().v('Requesting history...');
    await timeline?.requestHistory(historyCount: _loadHistoryCount);
  }

  Future<void> requestFuture() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    Logs().v('Requesting future...');

    final mostRecentEvent = timeline.events.filterByVisibleInGui().firstOrNull;

    await timeline.requestFuture(historyCount: _loadHistoryCount);

    if (mostRecentEvent != null) {
      setReadMarker(eventId: mostRecentEvent.eventId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = timeline.events.filterByVisibleInGui().indexOf(
          mostRecentEvent,
        );
        if (index >= 0) {
          scrollController.scrollToIndex(
            index,
            preferPosition: AutoScrollPosition.begin,
          );
        }
      });
    }
  }

  void _updateScrollController() {
    if (!mounted) {
      return;
    }
    if (!scrollController.hasClients) return;
    if (timeline?.allowNewEvent == false ||
        scrollController.position.pixels > 0 && _scrolledUp == false) {
      setState(() => _scrolledUp = true);
    } else if (scrollController.position.pixels <= 0 && _scrolledUp == true) {
      setState(() => _scrolledUp = false);
      setReadMarker();
    }
  }

  void _loadDraft() {
    final prefs = Matrix.of(context).store;
    final draft = prefs.getString('draft_$roomId');
    if (draft != null && draft.isNotEmpty) {
      sendController.text = draft;
      _inputTextIsEmpty = false;
    }
  }

  /// Ответ/редактирование из черновика восстанавливаем после загрузки
  /// таймлайна — раньше объекты Event ещё недоступны.
  void _restoreDraftReplyEdit() {
    if (!mounted || timeline == null) return;
    final prefs = Matrix.of(context).store;
    final replyId = prefs.getString('draft_${roomId}_reply');
    final editId = prefs.getString('draft_${roomId}_edit');
    var changed = false;
    if (replyId != null && replyId.isNotEmpty && replyEvent == null) {
      final event = timeline!.events
          .where((e) => e.eventId == replyId)
          .firstOrNull;
      if (event != null) {
        replyEvent = event;
        changed = true;
      }
    }
    if (editId != null && editId.isNotEmpty && editEvent == null) {
      final event = timeline!.events
          .where((e) => e.eventId == editId)
          .firstOrNull;
      if (event != null) {
        editEvent = event;
        sendController.text = event.plaintextBody;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  Future<void> _shareItems([_]) async {
    final shareItems = widget.shareItems;
    if (shareItems == null || shareItems.isEmpty) return;
    if (!room.otherPartyCanReceiveMessages) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          showCloseIcon: true,
        ),
      );
      return;
    }
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    for (final item in shareItems) {
      if (item is FileShareItem) continue;
      if (item is TextShareItem) room.sendTextEvent(item.value);
      if (item is ContentShareItem) room.sendEvent(item.value);
    }
    final files = shareItems
        .whereType<FileShareItem>()
        .map((item) => item.value)
        .toList();
    if (files.isEmpty) return;
    showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  KeyEventResult _customEnterKeyHandling(FocusNode node, KeyEvent evt) {
    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.arrowUp &&
        !PlatformInfos.isMobile &&
        editEvent == null &&
        replyEvent == null &&
        sendController.text.isEmpty) {
      _editLastSentMessage();
      return KeyEventResult.handled;
    }

    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.escape &&
        editEvent != null) {
      _cancelEditWithConfirmation();
      return KeyEventResult.handled;
    }

    if (!HardwareKeyboard.instance.isShiftPressed &&
        evt.logicalKey.keyLabel == 'Enter' &&
        AppSettings.sendOnEnter.value) {
      if (evt is KeyDownEvent) {
        send();
      }
      return KeyEventResult.handled;
    } else if (evt.logicalKey.keyLabel == 'Enter' && evt is KeyDownEvent) {
      final currentLineNum =
          sendController.text
              .substring(0, sendController.selection.baseOffset)
              .split('\n')
              .length -
          1;
      final currentLine = sendController.text.split('\n')[currentLineNum];

      for (final pattern in [
        '- [ ] ',
        '- [x] ',
        '* [ ] ',
        '* [x] ',
        '- ',
        '* ',
        '+ ',
      ]) {
        if (currentLine.startsWith(pattern)) {
          if (currentLine == pattern) {
            return KeyEventResult.ignored;
          }
          sendController.text += '\n$pattern';
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
  }

  @override
  void initState() {
    inputFocus = FocusNode(onKeyEvent: _customEnterKeyHandling);

    scrollController.addListener(_updateScrollController);
    inputFocus.addListener(_inputFocusListener);

    _loadDraft();
    WidgetsBinding.instance.addPostFrameCallback(_shareItems);
    web.window.addEventListener('paste', _handleClipboardFilePasteWeb);
    super.initState();
    _displayChatDetailsColumn = ValueNotifier(
      AppSettings.displayChatDetailsColumn.value,
    );

    bigEmojis = defaultEmojiSet.fold(
      <String>{},
      (emojis, category) => {
        ...emojis,
        ...(category.emoji.map((emoji) => emoji.emoji)),
      },
    );

    sendingClient = Matrix.of(context).client;
    final lastEventThreadId =
        room.lastEvent?.relationshipType == RelationshipTypes.thread
        ? room.lastEvent?.relationshipEventId
        : null;
    readMarkerEventId = room.hasNewMessages
        ? lastEventThreadId ?? room.fullyRead
        : '';
    WidgetsBinding.instance.addObserver(this);
    _tryLoadTimeline();
    _initScheduled();
  }

  List<ScheduledMessage> scheduledMessages = [];
  Timer? _scheduledTimer;

  /// Грузим очередь и сразу отправляем просроченное (приложение было закрыто).
  Future<void> _initScheduled() async {
    await _refreshScheduled();
    _armScheduledTimer();
  }

  /// Слить просроченное -> перезагрузить -> показать. Возврат при resume
  /// обязателен: one-shot Timer не срабатывает, пока приложение свернуто
  /// или чат закрыт, и сообщение «висело» бы молча.
  /// Если просроченное осталось после flush — отправка упала (сеть/сервер):
  /// показываем ошибку вместо тишины.
  Future<void> _refreshScheduled() async {
    final prefs = Matrix.of(context).store;
    scheduledMessages = await loadScheduled(prefs, roomId);
    if (!mounted) return;
    setState(() {});
    await flushDueScheduled(room, prefs);
    if (!mounted) return;
    scheduledMessages = await loadScheduled(prefs, roomId);
    setState(() {});
    final now = DateTime.now();
    if (mounted &&
        scheduledMessages.any((m) => !m.sendAt.isAfter(now))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось отправить отложенное (нет связи?). Оно осталось в очереди.',
          ),
        ),
      );
    }
  }

  void _armScheduledTimer() {
    _scheduledTimer?.cancel();
    final next = nextScheduledAt(scheduledMessages);
    if (next == null) return;
    final delay = next.difference(DateTime.now());
    _scheduledTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () async {
        if (!mounted) return;
        await _refreshScheduled();
        if (!mounted) return;
        _armScheduledTimer();
      },
    );
  }

  /// Долгое нажатие на «отправить»: запланировать вместо мгновенной отправки.
  Future<void> scheduleMessage() async {
    final text = sendController.text.trim();
    if (text.isEmpty) return;
    final at = await showScheduleDialog(context);
    if (at == null || !mounted) return;
    final prefs = Matrix.of(context).store;
    scheduledMessages = await loadScheduled(prefs, roomId);
    scheduledMessages.add(
      ScheduledMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        replyEventId: replyEvent?.eventId,
        sendAt: at,
      ),
    );
    await saveScheduled(prefs, roomId, scheduledMessages);
    sendController.clear();
    setState(() {
      replyEvent = null;
      _inputTextIsEmpty = true;
    });
    onInputBarChanged('');
    _armScheduledTimer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Отправка запланирована: $at'),
          action: SnackBarAction(
            label: 'Показать',
            onPressed: showScheduledList,
          ),
        ),
      );
    }
  }

  Future<void> cancelScheduled(String id) async {
    final prefs = Matrix.of(context).store;
    scheduledMessages = await loadScheduled(prefs, roomId);
    scheduledMessages.removeWhere((e) => e.id == id);
    await saveScheduled(prefs, roomId, scheduledMessages);
    if (mounted) setState(() {});
    _armScheduledTimer();
  }

  Future<void> showScheduledList() async {
    final prefs = Matrix.of(context).store;
    scheduledMessages = await loadScheduled(prefs, roomId);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Запланированные'),
        content: scheduledMessages.isEmpty
            ? const Text('Очередь пуста')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: scheduledMessages.length,
                  itemBuilder: (context, i) {
                    final item = scheduledMessages[i];
                    return ListTile(
                      title: Text(
                        item.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(item.sendAt.toString()),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outlined),
                        onPressed: () {
                          cancelScheduled(item.id);
                          Navigator.of(context).pop();
                        },
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (mounted) {
      scheduledMessages = await loadScheduled(
        Matrix.of(context).store,
        roomId,
      );
      setState(() {});
    }
  }

  final Set<String> expandedEventIds = {};

  void expandEventsFrom(Event event, bool expand) {
    final events = timeline!.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );
    final start = events.indexOf(event);
    setState(() {
      for (var i = start; i < events.length; i++) {
        final event = events[i];
        if (!event.isCollapsedState) return;
        if (expand) {
          expandedEventIds.add(event.eventId);
        } else {
          expandedEventIds.remove(event.eventId);
        }
      }
    });
  }

  Future<void> _tryLoadTimeline() async {
    final initialEventId = widget.eventId;
    loadTimelineFuture = _getTimeline();
    try {
      await loadTimelineFuture;
      final loadedTimeline = timeline;
      if (loadedTimeline == null) {
        // Загрузка не удалась (ошибка уже залогирована в
        // _loadTimelineInner). Не падаем на timeline! — остаёмся на
        // спиннере / баннере, повторная попытка будет при пересоздании.
        return;
      }
      _restoreDraftReplyEdit();
      // We launched the chat with a given initial event ID:
      if (initialEventId != null) {
        scrollToEventId(initialEventId);
        return;
      }

      var readMarkerEventIndex = readMarkerEventId.isEmpty
          ? -1
          : timeline!.events
                .filterByVisibleInGui(
                  exceptionEventId: readMarkerEventId,
                  threadId: activeThreadId,
                )
                .indexWhere((e) => e.eventId == readMarkerEventId);

      // Read marker is existing but not found in first events. Try a single
      // requestHistory call before opening timeline on event context:
      if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        await timeline?.requestHistory(historyCount: _loadHistoryCount);
        readMarkerEventIndex = timeline!.events
            .filterByVisibleInGui(
              exceptionEventId: readMarkerEventId,
              threadId: activeThreadId,
            )
            .indexWhere((e) => e.eventId == readMarkerEventId);
      }

      if (readMarkerEventIndex > 1) {
        Logs().v('Scroll up to visible event', readMarkerEventId);
        scrollToEventId(readMarkerEventId, highlightEvent: false);
        return;
      } else if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        _showScrollUpMaterialBanner(readMarkerEventId);
      }

      // Mark room as read on first visit if requirements are fulfilled
      setReadMarker();

      if (!mounted) return;
    } catch (e, s) {
      ErrorReporter(context, 'Unable to load timeline').onErrorCallback(e, s);
      rethrow;
    }
  }

  String? scrollUpBannerEventId;

  void discardScrollUpBannerEventId() => setState(() {
    scrollUpBannerEventId = null;
  });

  void _showScrollUpMaterialBanner(String eventId) => setState(() {
    scrollUpBannerEventId = eventId;
  });

  String? animateInEventId;

  Future<void> _insert(int index) async {
    if (index > 0) return;
    final firstEvent = timeline?.events.firstOrNull;
    final eventId = firstEvent?.transactionId ?? firstEvent?.eventId;
    animateInEventId = eventId;
    await Future.delayed(GalmaxThemes.animationDuration);
    if (animateInEventId == eventId) animateInEventId = null;
  }

  void updateView() {
    if (!mounted) return;
    setReadMarker();
    setState(() {});
  }

  Future<void>? loadTimelineFuture;

  Future<void> _getTimeline({String? eventContextId}) async {
    final matrix = Matrix.of(context);
    await matrix.client.roomsLoading;
    await matrix.client.accountDataLoading;
    if (eventContextId != null &&
        (!eventContextId.isValidMatrixId || eventContextId.sigil != '\$')) {
      eventContextId = null;
    }
    // Сериализуем с экспортом чата: параллельные getTimeline роняют
    // sqflite FFI (SqliteException 21, BEGIN IMMEDIATE).
    await TimelineMutex.run(() => _loadTimelineInner(eventContextId));
    final loadedTimeline = timeline;
    if (loadedTimeline == null) {
      // _loadTimelineInner уже залогировал ошибку и показал баннер.
      // Без throw: ChatEventList показывает спиннер при timeline == null,
      // а throw StateError превращался бы в краш FutureBuilder
      // «Null check operator used on a null value» на timeline!.
      if (!mounted) return;
      return;
    }
    loadedTimeline.requestKeys(onlineKeyBackupOnly: false);
    if (room.markedUnread) room.markUnread(false);

    return;
  }

  Future<void> _loadTimelineInner(String? eventContextId) async {
    // Транзитный лок sqlite (фон-синк пишет в тот же файл из другого
    // изолята): ретраим с бэкоффом вместо мгновенного падения.
    // SqliteException(21) BEGIN IMMEDIATE / 'database is locked' — ждём и
    // пробуем снова, всего до 4 попыток. Плюс жёсткий таймаут на попытку:
    // зависшее чтение (лок без исключения) превращаем в TimeoutException
    // и тоже ретраим — иначе спиннер «загрузка, подождите» крутится вечно.
    // Сами сообщения уже лежат на диске (sqlite), повторный вход читает
    // их локально; тормозит именно заблокированная транзакция или
    // расшифровка пачки событий.
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 150 * attempt));
      }
      try {
        timeline?.cancelSubscriptions();
        timeline = await room
            .getTimeline(
              onUpdate: updateView,
              onInsert: _insert,
              eventContextId: eventContextId,
            )
            .timeout(const Duration(seconds: 10));
        return;
      } catch (e, s) {
        lastError = e;
        lastStack = s;
        if (!_isTransientDbError(e) || attempt == 3) break;
        Logs().d(
          '[Chat] getTimeline transient DB lock, retry ${attempt + 1}/4',
          e,
        );
      }
    }
    final e = lastError;
    final s = lastStack;
    Logs().w('Unable to load timeline on event ID $eventContextId', e, s);
    if (!mounted) return;
    // Фолбэк без eventContext — легче для базы, часто проходит.
    try {
      timeline = await room
          .getTimeline(onUpdate: updateView)
          .timeout(const Duration(seconds: 15));
    } catch (e2, s2) {
      Logs().w('Unable to load timeline fallback', e2, s2);
      if (!mounted) return;
      if (e2 is TimeoutException || e2 is IOException) {
        final ctx = eventContextId;
        if (ctx != null && ctx.isNotEmpty) {
          _showScrollUpMaterialBanner(ctx);
        }
      }
      return;
    }
    if (!mounted) return;
    if (e is TimeoutException || e is IOException) {
      final ctx = eventContextId;
      if (ctx != null && ctx.isNotEmpty) {
        _showScrollUpMaterialBanner(ctx);
      }
    }
  }

  static bool _isTransientDbError(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString();
    return s.contains('SqliteException(21)') ||
        s.contains('BEGIN IMMEDIATE') ||
        s.contains('bad parameter or other API misuse') ||
        s.contains('database is locked') ||
        s.contains('database table is locked') ||
        s.contains('DatabaseException');
  }

  String? scrollToEventIdMarker;

  /// Первое непрочитанное в загруженном таймлайне (для кнопки «вниз
  /// к непрочитанным»). Null — нечего показывать.
  String? get firstUnreadEventId {
    final tl = timeline;
    if (tl == null || tl.events.isEmpty) return null;
    if (!room.hasNewMessages && room.notificationCount == 0) return null;
    if (readMarkerEventId.isEmpty) return null;
    final found = tl.events.any((e) => e.eventId == readMarkerEventId);
    return found ? readMarkerEventId : null;
  }

  /// Последнее упоминание меня в загруженном таймлайне (кнопка «@»).
  String? get lastMentionEventId {
    final tl = timeline;
    if (tl == null || tl.events.isEmpty) return null;
    final ownId = room.client.userID;
    if (ownId == null) return null;
    final localpart = ownId.localpart;
    for (final event in tl.events) {
      if (event.senderId == ownId) continue;
      if (event.type != EventTypes.Message &&
          event.type != EventTypes.Encrypted &&
          event.type != EventTypes.Sticker) {
        continue;
      }
      final mentions = event.content['m.mentions'];
      if (mentions is Map) {
        final userIds = mentions['user_ids'];
        if (userIds is List && userIds.contains(ownId)) return event.eventId;
      }
      if (localpart != null && event.plaintextBody.contains('@$localpart')) {
        return event.eventId;
      }
    }
    return null;
  }

  void jumpToFirstUnread() {
    final eventId = firstUnreadEventId ?? scrollUpBannerEventId;
    if (eventId == null) {
      scrollDown();
      return;
    }
    scrollToEventId(eventId, highlightEvent: false);
    if (eventId == scrollUpBannerEventId) discardScrollUpBannerEventId();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    setReadMarker();
    // Долгое нажатие-таймер мог пропустить время в фоне — догоняем.
    _refreshScheduled().then((_) {
      if (mounted) _armScheduledTimer();
    });
  }

  Future<void>? _setReadMarkerFuture;

  void setReadMarker({String? eventId}) {
    if (eventId?.isValidMatrixId == false) return;
    if (_setReadMarkerFuture != null) return;
    if (_scrolledUp) return;
    if (scrollUpBannerEventId != null) return;

    if (eventId == null &&
        !room.hasNewMessages &&
        room.notificationCount == 0) {
      return;
    }

    // Do not send read markers when app is not in foreground
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final timeline = this.timeline;
    if (timeline == null || timeline.events.isEmpty) return;

    Logs().d('Set read marker...', eventId);
    // ignore: unawaited_futures
    _setReadMarkerFuture = timeline
        .setReadMarker(
          eventId: eventId,
          public: AppSettings.sendPublicReadReceipts.value,
        )
        .then((_) {
          _setReadMarkerFuture = null;
        });
  }

  @override
  void dispose() {
    timeline?.cancelSubscriptions();
    timeline = null;
    _storeInputTimeoutTimer?.cancel();
    _scheduledTimer?.cancel();
    typingCoolDown?.cancel();
    typingTimeout?.cancel();
    sendController.dispose();
    scrollController.dispose();
    inputFocus.removeListener(_inputFocusListener);
    inputFocus.dispose();
    web.window.removeEventListener('paste', _handleClipboardFilePasteWeb);
    if (currentlyTyping) room.setTyping(false);
    MxcImage.clearCache(widget.room.id);
    super.dispose();
  }

  TextEditingController sendController = TextEditingController();

  void setSendingClient(Client c) {
    // first cancel typing with the old sending client
    if (currentlyTyping) {
      // no need to have the setting typing to false be blocking
      typingCoolDown?.cancel();
      typingCoolDown = null;
      room.setTyping(false);
      currentlyTyping = false;
    }
    // then cancel the old timeline
    // fixes bug with read reciepts and quick switching
    loadTimelineFuture = _getTimeline(eventContextId: room.fullyRead).onError(
      ErrorReporter(
        context,
        'Unable to load timeline after changing sending Client',
      ).onErrorCallback,
    );

    // then set the new sending client
    setState(() => sendingClient = c);
  }

  void setActiveClient(Client c) => setState(() {
    Matrix.of(context).setActiveClient(c);
  });

  Future<void> send() async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    if (sendController.text.trim().isEmpty) return;
    _storeInputTimeoutTimer?.cancel();
    final prefs = Matrix.of(context).store;
    prefs.remove('draft_$roomId');
    prefs.remove('draft_${roomId}_reply');
    prefs.remove('draft_${roomId}_edit');
    var parseCommands = true;

    final commandMatch = RegExp(r'^\/(\w+)').firstMatch(sendController.text);
    if (commandMatch != null &&
        !sendingClient.commands.keys.contains(commandMatch[1]!.toLowerCase())) {
      final l10n = L10n.of(context);
      final dialogResult = await showOkCancelAlertDialog(
        context: context,
        title: l10n.commandInvalid,
        message: l10n.commandMissing(commandMatch[0]!),
        okLabel: l10n.sendAsText,
        cancelLabel: l10n.cancel,
      );
      if (dialogResult == OkCancelResult.cancel) return;
      parseCommands = false;
    }

    // ignore: unawaited_futures
    room.sendTextEvent(
      sendController.text,
      inReplyTo: replyEvent,
      editEventId: editEvent?.eventId,
      parseCommands: parseCommands,
      threadRootEventId: activeThreadId,
    );
    sendController.value = TextEditingValue(
      text: pendingText,
      selection: const TextSelection.collapsed(offset: 0),
    );

    setState(() {
      sendController.text = pendingText;
      _inputTextIsEmpty = pendingText.isEmpty;
      replyEvent = null;
      editEvent = null;
      pendingText = '';
    });
  }

  Future<void> sendFileAction({FileType type = FileType.any}) async {
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty) return;
    if (!mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> sendImageFromClipBoard(Uint8List? image) async {
    if (image == null) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [XFile.fromData(image)],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> openCameraAction() async {
    // Make sure the textfield is unfocused before opening the camera
    FocusScope.of(context).requestFocus(FocusNode());
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;
    if (!mounted) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> _handleClipboardFilePasteWeb(web.Event event) async {
    if (event is! web.ClipboardEvent) return;

    final clipboardFiles = event.clipboardData?.files;
    final length = clipboardFiles?.length ?? 0;
    if (clipboardFiles == null || length < 1) return;

    // Browser will clear clipboardData when we await!
    // We MUST extract the files synchronously first.
    final localFiles = clipboardFiles.toList();

    if (localFiles.isEmpty) return;

    event.preventDefault();
    event.stopPropagation();

    final xFilesResult = await showFutureLoadingDialog(
      context: context,
      future: () async {
        // Convert one after another seems to be more stable
        final xFiles = <XFile>[];
        for (final file in localFiles) {
          xFiles.add(await webToXFile(file));
        }
        return xFiles;
      },
    );
    final xFiles = xFilesResult.result;
    if (xFiles == null || xFiles.isEmpty) return;

    if (!mounted) return;
    showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: xFiles,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> _handleClipboardImagePaste() async {
    final files = await Pasteboard.files();
    if (files.isNotEmpty) {
      if (!mounted) return;
      await showAdaptiveDialog(
        context: context,
        builder: (c) => SendFileDialog(
          files: files.map(XFile.new).toList(),
          room: room,
          outerContext: context,
          threadRootEventId: activeThreadId,
          threadLastEventId: threadLastEventId,
        ),
      );
      return;
    }
    final image = await Pasteboard.image;
    if (image != null) {
      await sendImageFromClipBoard(image);
      return;
    }
    // No image in clipboard — fall back to pasting text
    final textData = await Clipboard.getData('text/plain');
    if (textData?.text != null) {
      final selection = sendController.selection;
      final text = sendController.text;
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        textData!.text!,
      );
      sendController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + textData.text!.length,
        ),
      );
      onInputBarChanged(sendController.text);
    }
  }

  Future<void> openVideoCameraAction() async {
    // Make sure the textfield is unfocused before opening the camera
    FocusScope.of(context).requestFocus(FocusNode());
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    if (file == null) return;
    if (!mounted) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  void openRoundVideoAction() {
    FocusScope.of(context).requestFocus(FocusNode());
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            RoundVideoOverlay(
          room: room,
          onClose: () {
            Navigator.of(context).pop();
          },
          threadRootEventId: activeThreadId,
          threadLastEventId: threadLastEventId,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> onVoiceMessageSend(
    String path,
    int duration,
    List<int> waveform,
    String fileName,
  ) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    // Собеседник (GalMax) видит «отправляет голосовое…», чужие — «печатает…».
    GalmaxActivity.send(room, GalmaxActivity.sendingVoice);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final audioFile = XFile(path);

    final bytesResult = await showFutureLoadingDialog(
      context: context,
      future: audioFile.readAsBytes,
    );
    final bytes = bytesResult.result;
    if (bytes == null) {
      GalmaxActivity.stopActivity(room);
      return;
    }

    final mimeType = lookupMimeType(fileName, headerBytes: bytes);
    final extension = mimeType == null ? null : extensionFromMime(mimeType);
    if (extension != null) {
      fileName =
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.$extension';
    }

    final file = MatrixAudioFile(
      bytes: bytes,
      name: fileName,
      mimeType: mimeType,
    );

    try {
      await room.sendFileEvent(
        file,
        inReplyTo: replyEvent,
        threadRootEventId: activeThreadId,
        extraContent: {
          'info': {...file.info, 'duration': duration},
          'org.matrix.msc3245.voice': {},
          'org.matrix.msc1767.audio': {
            'duration': duration,
            'waveform': waveform,
          },
        },
      );
    } catch (e) {
      GalmaxActivity.stopActivity(room);
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
      return;
    }
    GalmaxActivity.stopActivity(room);
    setState(() {
      replyEvent = null;
    });
    return;
  }

  void hideEmojiPicker() {
    setState(() => showEmojiPicker = false);
  }

  void emojiPickerAction() {
    if (showEmojiPicker) {
      inputFocus.requestFocus();
    } else {
      inputFocus.unfocus();
    }
    setState(() => showEmojiPicker = !showEmojiPicker);
  }

  void _inputFocusListener() {
    if (showEmojiPicker && inputFocus.hasFocus) {
      setState(() => showEmojiPicker = false);
    }
  }

  Future<void> sendLocationAction() async {
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendLocationDialog(room: room),
    );
  }

  String _getSelectedEventString() {
    var copyString = '';
    if (selectedEvents.length == 1) {
      return selectedEvents.first
          .getDisplayEvent(timeline!)
          .calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)));
    }
    for (final event in selectedEvents) {
      if (copyString.isNotEmpty) copyString += '\n\n';
      copyString += event
          .getDisplayEvent(timeline!)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: true,
          );
    }
    return copyString;
  }

  void copyEventsAction() {
    Clipboard.setData(ClipboardData(text: _getSelectedEventString()));
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  Future<void> reportEventAction() async {
    final event = selectedEvents.single;
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!mounted) return;
    final reason = await showTextInputDialog(
      context: context,
      title: l10n.whyDoYouWantToReportThis,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.reason,
    );
    if (reason == null || reason.isEmpty) return;
    if (!mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(
        context,
      ).client.reportEvent(event.roomId!, event.eventId, reason: reason),
    );
    if (result.error != null) return;
    if (!mounted) return;
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(l10n.contentHasBeenReported)),
    );
  }

  Future<void> deleteErrorEventsAction() async {
    try {
      if (selectedEvents.any((event) => event.status != EventStatus.error)) {
        throw Exception(
          'Tried to delete failed to send events but one event is not failed to sent',
        );
      }
      for (final event in selectedEvents) {
        await event.cancelSend();
      }
      setState(selectedEvents.clear);
    } catch (e, s) {
      if (!mounted) return;
      ErrorReporter(
        context,
        'Error while delete error events action',
      ).onErrorCallback(e, s);
    }
  }

  Future<void> redactEventsAction() async {
    final hasSent = selectedEvents.any((event) => event.status.isSent);
    final reasonInput = hasSent
        ? await showTextInputDialog(
            context: context,
            title: L10n.of(context).redactMessage,
            message: L10n.of(context).redactMessageDescription,
            isDestructive: true,
            hintText: L10n.of(context).optionalRedactReason,
            maxLength: 255,
            maxLines: 3,
            minLines: 1,
            okLabel: L10n.of(context).remove,
            cancelLabel: L10n.of(context).cancel,
          )
        : '';
    if (!mounted) return;
    // Крестик/отмена: null — выходим молча, не блокируя чат.
    if (hasSent && reasonInput == null) return;
    final reason = (reasonInput ?? '').isEmpty ? null : reasonInput;
    final events = List<Event>.from(selectedEvents);
    final total = events.length;
    // Снимаем выделение сразу — чат не блокируется, удаление идёт в фоне
    // по очереди с паузой (bulk redact в Matrix нет).
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Удаление 0/$total…'),
        duration: const Duration(seconds: 2),
      ),
    );
    var done = 0;
    var failed = 0;
    // ignore: unawaited_futures
    () async {
      for (final event in events) {
        try {
          if (event.status.isSent) {
            if (event.canRedact) {
              await event.redactEvent(reason: reason);
            } else {
              // Клиент ищем по автору КАЖДОГО события, а не первого:
              // иначе пачка от разных отправителей уходила не туда.
              final client = currentRoomBundle.firstWhereOrNull(
                (cl) => event.senderId == cl?.userID,
              );
              if (client == null) {
                failed++;
                continue;
              }
              final room = client.getRoomById(roomId);
              if (room == null) {
                failed++;
                continue;
              }
              await Event.fromJson(
                event.toJson(),
                room,
              ).redactEvent(reason: reason);
            }
          } else {
            await event.cancelSend();
          }
          done++;
        } catch (e, s) {
          failed++;
          Logs().w('Background redact failed ${event.eventId}', e, s);
        }
        if (events.length > 1 && event != events.last) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? (total == 1
                      ? 'Сообщение удалено'
                      : 'Сообщения удалены ($done)')
                : 'Удалено $done, ошибок: $failed',
          ),
        ),
      );
      setState(() {});
    }();
  }

  List<Client?> get currentRoomBundle {
    final clients = Matrix.of(context).currentBundle!;
    clients.removeWhere((c) => c!.getRoomById(roomId) == null);
    return clients;
  }

  bool get canRedactSelectedEvents {
    if (isArchived) return false;
    final clients = Matrix.of(context).currentBundle;
    for (final event in selectedEvents) {
      if (!event.status.isSent) return false;
      if (event.canRedact == false &&
          !(clients!.any((cl) => event.senderId == cl!.userID))) {
        return false;
      }
    }
    return true;
  }

  bool get canPinSelectedEvents {
    if (isArchived ||
        !room.canChangeStateEvent(EventTypes.RoomPinnedEvents) ||
        selectedEvents.length != 1 ||
        !selectedEvents.single.status.isSent ||
        activeThreadId != null) {
      return false;
    }
    return true;
  }

  bool get canEditSelectedEvents {
    if (isArchived ||
        selectedEvents.length != 1 ||
        !selectedEvents.first.status.isSent) {
      return false;
    }
    return currentRoomBundle.any(
      (cl) => selectedEvents.first.senderId == cl!.userID,
    );
  }

  Future<void> forwardEventsAction() async {
    if (selectedEvents.isEmpty) return;
    final timeline = this.timeline;
    if (timeline == null) return;

    final forwardEvents = List<Event>.from(
      selectedEvents,
    ).map((event) => event.getDisplayEvent(timeline)).toList();

    await showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialog(
        items: forwardEvents
            .map((event) => ContentShareItem(event.content.copy()))
            .toList(),
      ),
    );
    if (!mounted) return;
    setState(() => selectedEvents.clear());
  }

  void sendAgainAction() {
    final event = selectedEvents.first;
    if (event.status.isError) {
      event.sendAgain();
    }
    final allEditEvents = event
        .aggregatedEvents(timeline!, RelationshipTypes.edit)
        .where((e) => e.status.isError);
    for (final e in allEditEvents) {
      e.sendAgain();
    }
    setState(() => selectedEvents.clear());
  }

  void replyAction({Event? replyTo}) {
    setState(() {
      replyEvent = replyTo ?? selectedEvents.first;
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  Future<void> scrollToEventId(
    String eventId, {
    bool highlightEvent = true,
  }) async {
    final foundEvent = timeline!.events.firstWhereOrNull(
      (event) => event.eventId == eventId,
    );

    final eventIndex = foundEvent == null
        ? -1
        : timeline!.events
              .filterByVisibleInGui(
                exceptionEventId: eventId,
                threadId: activeThreadId,
              )
              .indexOf(foundEvent);

    if (eventIndex == -1) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline(eventContextId: eventId).onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll to ID',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        scrollToEventId(eventId);
      });
      return;
    }
    if (highlightEvent) {
      setState(() {
        scrollToEventIdMarker = eventId;
      });
    }
    await scrollController.scrollToIndex(
      eventIndex + 1,
      duration: GalmaxThemes.animationDuration,
      preferPosition: AutoScrollPosition.middle,
    );
    _updateScrollController();
  }

  Future<void> scrollDown() async {
    if (!timeline!.allowNewEvent) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline().onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll down',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
    }
    scrollController.jumpTo(0);
  }

  void onEmojiSelected(_, Emoji? emoji) {
    typeEmoji(emoji);
    onInputBarChanged(sendController.text);
  }

  void typeEmoji(Emoji? emoji) {
    if (emoji == null) return;
    final text = sendController.text;
    final selection = sendController.selection;
    final newText = sendController.text.isEmpty
        ? emoji.emoji
        : text.replaceRange(selection.start, selection.end, emoji.emoji);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        // don't forget an UTF-8 combined emoji might have a length > 1
        offset: selection.baseOffset + emoji.emoji.length,
      ),
    );
  }

  void emojiPickerBackspace() {
    sendController
      ..text = sendController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: sendController.text.length),
      );
  }

  void clearSelectedEvents() => setState(() {
    selectedEvents.clear();
    showEmojiPicker = false;
  });

  void clearSingleSelectedEvent() {
    if (selectedEvents.length <= 1) {
      clearSelectedEvents();
    }
  }

  void _startEditingEvent(Event event, {bool clearSelection = false}) {
    final timeline = this.timeline;
    if (timeline == null) return;

    final client = currentRoomBundle.firstWhere(
      (c) => c?.userID == event.senderId,
      orElse: () => null,
    );
    if (client == null) return;

    setSendingClient(client);
    setState(() {
      pendingText = sendController.text;
      editEvent = event;
      sendController.text = event
          .getDisplayEvent(timeline)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: false,
            hideReply: true,
          );
      if (clearSelection) selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void editSelectedEventAction() {
    _startEditingEvent(selectedEvents.first, clearSelection: true);
  }

  void _editLastSentMessage() {
    final timeline = this.timeline;
    if (timeline == null) return;

    final events = timeline.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );

    final lastOwnMessage = events.firstWhereOrNull(
      (e) =>
          e.type == EventTypes.Message &&
          e.messageType == MessageTypes.Text &&
          e.status.isSent &&
          !e.redacted &&
          currentRoomBundle.any((c) => c?.userID == e.senderId),
    );

    if (lastOwnMessage == null) return;

    _startEditingEvent(lastOwnMessage);
  }

  Future<void> goToNewRoomAction() async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final users = await room.requestParticipants(
          [Membership.join, Membership.leave],
          true,
          false,
        );
        users.sort((a, b) => a.powerLevel.level.compareTo(b.powerLevel.level));
        final via = users
            .map((user) => user.id.domain)
            .whereType<String>()
            .toSet()
            .take(10)
            .toList();
        return room.client.joinRoom(
          room
              .getState(EventTypes.RoomTombstone)!
              .parsedTombstoneContent
              .replacementRoom,
          via: via,
        );
      },
    );
    if (result.error != null) return;
    if (!mounted) return;
    context.go('/rooms/${result.result!}');

    await showFutureLoadingDialog(context: context, future: room.leave);
  }

  void onSelectMessage(Event event) {
    if (!event.redacted) {
      if (selectedEvents.contains(event)) {
        setState(() => selectedEvents.remove(event));
      } else {
        setState(() => selectedEvents.add(event));
      }
      selectedEvents.sort(
        (a, b) => a.originServerTs.compareTo(b.originServerTs),
      );
    }
  }

  int? findChildIndexCallback(Key key, Map<String, int> thisEventsKeyMap) {
    // this method is called very often. As such, it has to be optimized for speed.
    if (key is! ValueKey) {
      return null;
    }
    final eventId = key.value;
    if (eventId is! String) {
      return null;
    }
    // first fetch the last index the event was at
    final index = thisEventsKeyMap[eventId];
    if (index == null) {
      return null;
    }
    // we need to +1 as 0 is the typing thing at the bottom
    return index + 1;
  }

  void onInputBarSubmitted(String _) {
    send();
    FocusScope.of(context).requestFocus(inputFocus);
  }

  void onAddPopupMenuButtonSelected(AddPopupMenuActions choice) {
    room.client.getConfig();

    switch (choice) {
      case AddPopupMenuActions.image:
        sendFileAction(type: FileType.image);
        return;
      case AddPopupMenuActions.video:
        sendFileAction(type: FileType.video);
        return;
      case AddPopupMenuActions.file:
        sendFileAction();
        return;
      case AddPopupMenuActions.poll:
        showAdaptiveBottomSheet(
          context: context,
          builder: (context) => StartPollBottomSheet(room: room),
        );
        return;
      case AddPopupMenuActions.photoCamera:
        openCameraAction();
        return;
      case AddPopupMenuActions.videoCamera:
        openVideoCameraAction();
        return;
      case AddPopupMenuActions.roundVideo:
        openRoundVideoAction();
        return;
      case AddPopupMenuActions.location:
        sendLocationAction();
        return;
    }
  }

  Future<void> unpinEvent(String eventId) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).unpin,
      message: L10n.of(context).confirmEventUnpin,
      okLabel: L10n.of(context).unpin,
      cancelLabel: L10n.of(context).cancel,
    );
    if (!mounted) return;
    if (response == OkCancelResult.ok) {
      final events = room.pinnedEventIds
        ..removeWhere((oldEvent) => oldEvent == eventId);
      showFutureLoadingDialog(
        context: context,
        future: () => room.setPinnedEvents(events),
      );
    }
  }

  void pinEvent() {
    final pinnedEventIds = room.pinnedEventIds;
    final selectedEventIds = selectedEvents.map((e) => e.eventId).toSet();
    final unpin =
        selectedEventIds.length == 1 &&
        pinnedEventIds.contains(selectedEventIds.single);
    if (unpin) {
      pinnedEventIds.removeWhere(selectedEventIds.contains);
    } else {
      pinnedEventIds.addAll(selectedEventIds);
    }
    showFutureLoadingDialog(
      context: context,
      future: () => room.setPinnedEvents(pinnedEventIds),
    );
  }

  Timer? _storeInputTimeoutTimer;
  static const Duration _storeInputTimeout = Duration(milliseconds: 500);

  double? inputBarHeight;

  void updateInputBarHeight() {
    RenderBox? renderBox;
    if (inputBarKey.currentContext?.findRenderObject() != null) {
      renderBox = inputBarKey.currentContext!.findRenderObject() as RenderBox;
    }

    final height = renderBox?.size.height ?? 72.0;
    if (height != inputBarHeight) {
      setState(() {
        inputBarHeight = height;
      });
    }
  }

  void onInputBarChanged(String text) {
    if (_inputTextIsEmpty != text.isEmpty) {
      setState(() {
        _inputTextIsEmpty = text.isEmpty;
      });
    }

    _storeInputTimeoutTimer?.cancel();
    _storeInputTimeoutTimer = Timer(_storeInputTimeout, () async {
      final prefs = Matrix.of(context).store;
      await prefs.setString('draft_$roomId', text);
      final replyId = replyEvent?.eventId;
      if (replyId != null) {
        await prefs.setString('draft_${roomId}_reply', replyId);
      } else {
        await prefs.remove('draft_${roomId}_reply');
      }
      final editId = editEvent?.eventId;
      if (editId != null) {
        await prefs.setString('draft_${roomId}_edit', editId);
      } else {
        await prefs.remove('draft_${roomId}_edit');
      }
    });
    if (text.endsWith(' ') && Matrix.of(context).hasComplexBundles) {
      final clients = currentRoomBundle;
      for (final client in clients) {
        final prefix = client!.sendPrefix;
        if ((prefix.isNotEmpty) &&
            text.toLowerCase() == '${prefix.toLowerCase()} ') {
          setSendingClient(client);
          setState(() {
            sendController.clear();
          });
          return;
        }
      }
    }
    if (AppSettings.sendTypingNotifications.value) {
      typingCoolDown?.cancel();
      typingCoolDown = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        typingCoolDown = null;
        currentlyTyping = false;
        room.setTyping(false);
      });
      typingTimeout ??= Timer(const Duration(seconds: 30), () {
        typingTimeout = null;
        currentlyTyping = false;
      });
      if (!currentlyTyping) {
        currentlyTyping = true;
        room.setTyping(
          true,
          timeout: const Duration(seconds: 30).inMilliseconds,
        );
      }
    }
  }

  bool _inputTextIsEmpty = true;

  bool get isArchived =>
      {Membership.leave, Membership.ban}.contains(room.membership);

  void showEventInfo([Event? event]) =>
      (event ?? selectedEvents.single).showInfoDialog(context);

  Future<void> onPhoneButtonTap() async {
    // VoIP required Android SDK 21
    if (PlatformInfos.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      if (androidInfo.version.sdkInt < 21) {
        Navigator.pop(context);
        await showOkAlertDialog(
          context: context,
          title: L10n.of(context).unsupportedAndroidVersion,
          message: L10n.of(context).unsupportedAndroidVersionLong,
          okLabel: L10n.of(context).close,
        );
        return;
      }
    }
    final callType = await showModalActionPopup<Object>(
      context: context,
      title: L10n.of(context).placeCall,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).voiceCall,
          icon: const Icon(Icons.phone_outlined),
          value: CallType.kVoice,
        ),
        AdaptiveModalAction(
          label: L10n.of(context).videoCall,
          icon: const Icon(Icons.video_call_outlined),
          value: CallType.kVideo,
        ),
        // Обычный звонок через звонилку Android: номер берётся из
        // телефонной книги (см. «Позвонить» в профиле). Только для личек.
        AdaptiveModalAction(
          label: 'По телефону',
          icon: const Icon(Icons.call_outlined),
          value: 'phone',
        ),
      ],
    );
    if (callType == null) return;
    if (!mounted) return;

    if (callType == 'phone') {
      final dmId = room.directChatMatrixID;
      if (dmId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Звонок по телефону — только для личных чатов'),
          ),
        );
        return;
      }
      await callMatrixUserFromContacts(
        context,
        userId: dmId,
        displayName: room.getLocalizedDisplayname(),
      );
      return;
    }

    final voipPlugin = Matrix.of(context).voipPlugin;
    try {
      await voipPlugin!.voip.inviteToCall(
        room,
        callType as CallType,
        userId: room.directChatMatrixID,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    }
  }

  void cancelReplyEventAction() => setState(() {
    if (editEvent != null) {
      sendController.text = pendingText;
      pendingText = '';
    }
    replyEvent = null;
    editEvent = null;
  });

  Future<void> _cancelEditWithConfirmation() async {
    final originalText = editEvent!
        .getDisplayEvent(timeline!)
        .calcLocalizedBodyFallback(
          MatrixLocals(L10n.of(context)),
          withSenderNamePrefix: false,
          hideReply: true,
        );

    if (sendController.text != originalText) {
      final result = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).areYouSure,
        message: L10n.of(context).discardEdits,
        okLabel: L10n.of(context).ok,
        cancelLabel: L10n.of(context).cancel,
      );
      if (result == OkCancelResult.cancel) return;
    }

    cancelReplyEventAction();
  }

  late final ValueNotifier<bool> _displayChatDetailsColumn;

  Future<void> toggleDisplayChatDetailsColumn() async {
    await AppSettings.displayChatDetailsColumn.setItem(
      !_displayChatDetailsColumn.value,
    );
    _displayChatDetailsColumn.value = !_displayChatDetailsColumn.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      actions: kIsWeb
          ? {}
          : <Type, Action<Intent>>{
              PasteTextIntent: CallbackAction<PasteTextIntent>(
                onInvoke: (PasteTextIntent intent) =>
                    _handleClipboardImagePaste(),
              ),
            },
      child: Row(
        children: [
          Expanded(child: ChatView(this)),
          ValueListenableBuilder(
            valueListenable: _displayChatDetailsColumn,
            builder: (context, displayChatDetailsColumn, _) =>
                !GalmaxThemes.isThreeColumnMode(context) ||
                    room.membership != Membership.join ||
                    !displayChatDetailsColumn
                ? const SizedBox(height: double.infinity, width: 0)
                : Container(
                    width: GalmaxThemes.columnWidth,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(width: 1, color: theme.dividerColor),
                      ),
                    ),
                    child: ChatDetails(
                      roomId: roomId,
                      embeddedCloseButton: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: toggleDisplayChatDetailsColumn,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

enum AddPopupMenuActions {
  image,
  video,
  file,
  poll,
  photoCamera,
  videoCamera,
  roundVideo,
  location,
}
