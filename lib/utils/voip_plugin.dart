// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:core';

import 'package:galmax/pages/dialer/dialer.dart';
import 'package:galmax/utils/call_notification_helper.dart';
import 'package:galmax/utils/call_ring_player.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc_impl;
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' hide Navigator;

import '../widgets/matrix.dart';

/// Audio device types matching Element Android's CallAudioManager
enum AudioDeviceType { speaker, earpiece, bluetooth, wired, unknown }

class VoipPlugin with WidgetsBindingObserver implements WebRTCDelegate {
  final MatrixState matrix;
  Client get client => matrix.client;
  VoipPlugin(this.matrix) {
    voip = VoIP(client, this);
    if (!kIsWeb) {
      final wb = WidgetsBinding.instance;
      wb.addObserver(this);
      didChangeAppLifecycleState(wb.lifecycleState);
      // Initialize foreground task once
      _initForegroundTask();
      // Просим камеру+микрофон заранее, пока приложение на виду.
      // Иначе первый входящий видео-звонок умирает в фоне молча:
      // SDK в initWithInvite дёргает getUserMedia(video), диалог
      // разрешений на локскрине показать нельзя — до handleNewCall
      // дело не доходит и остаётся только пуш "начал звонок".
      unawaited(_warmUpCallPermissions());
    }
  }
  bool background = false;
  bool speakerOn = false;
  late VoIP voip;
  OverlayEntry? overlayEntry;
  BuildContext? context;
  final Set<String> _notifiedCalls = {};
  final Map<String, CallSession> _pendingCalls = {};
  bool _foregroundTaskInitialized = false;

  void _initForegroundTask() {
    if (_foregroundTaskInitialized) return;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'galmax_call_active',
          channelName: 'Активный звонок',
          channelDescription: 'Звонок активен',
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
        ),
      );
      _foregroundTaskInitialized = true;
    } catch (e) {
      Logs().e('[VOIP] Failed to init foreground task', e);
    }
  }

  // Audio device management (like Element Android's CallAudioManager)
  AudioDeviceType _selectedDevice = AudioDeviceType.unknown;
  AudioDeviceType get selectedDevice => _selectedDevice;
  List<MediaDeviceInfo> _availableAudioOutputs = [];
  List<MediaDeviceInfo> get availableAudioOutputs => _availableAudioOutputs;

  /// Прогрев разрешений: один короткий getUserMedia + сразу стоп.
  /// Без новой зависимости — системный диалог показывает сам WebRTC.
  Future<void> _warmUpCallPermissions() async {
    try {
      final stream = await mediaDevices.getUserMedia({
        'audio': true,
        'video': true,
      });
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
      Logs().v('[VOIP] Call permissions warmed up');
    } catch (e) {
      Logs().w('[VOIP] Call permission warm-up failed, will ask on call', e);
    }
  }

  /// Detect available audio output devices
  Future<void> _refreshAudioDevices() async {
    try {
      _availableAudioOutputs = await Helper.enumerateDevices('audiooutput');
    } catch (e) {
      Logs().e('[VOIP] Failed to enumerate audio devices', e);
    }
  }

  /// Set default audio route based on call type (like Element Android)
  /// - Voice call: earpiece (or BT if available)
  /// - Video call: speaker
  Future<void> setDefaultAudioRoute(CallSession call) async {
    if (kIsWeb) return;
    try {
      await _refreshAudioDevices();
      final hasBluetooth = _availableAudioOutputs.any(
        (d) =>
            d.kind == 'audiooutput' &&
            (d.label.toLowerCase().contains('bluetooth') ||
                d.deviceId.contains('BT')),
      );

      if (call.type == CallType.kVideo) {
        // Video calls default to speaker
        await Helper.setSpeakerphoneOn(true);
        _selectedDevice = AudioDeviceType.speaker;
        speakerOn = true;
      } else {
        // Voice calls default to earpiece (or BT if available)
        if (hasBluetooth) {
          await Helper.setSpeakerphoneOnButPreferBluetooth();
          _selectedDevice = AudioDeviceType.bluetooth;
        } else {
          await Helper.setSpeakerphoneOn(false);
          _selectedDevice = AudioDeviceType.earpiece;
        }
        speakerOn = false;
      }
    } catch (e) {
      Logs().e('[VOIP] Failed to set default audio route', e);
    }
  }

  /// Toggle between speaker and earpiece (like Element Android)
  Future<void> toggleSpeaker() async {
    if (kIsWeb) return;
    try {
      speakerOn = !speakerOn;
      await Helper.setSpeakerphoneOn(speakerOn);
      _selectedDevice = speakerOn
          ? AudioDeviceType.speaker
          : AudioDeviceType.earpiece;
    } catch (e) {
      Logs().e('[VOIP] Failed to toggle speaker', e);
    }
  }

  /// Force a specific audio device (like Element Android's setAudioDevice)
  Future<void> setAudioDevice(AudioDeviceType device) async {
    if (kIsWeb) return;
    try {
      await _refreshAudioDevices();
      switch (device) {
        case AudioDeviceType.speaker:
          await Helper.setSpeakerphoneOn(true);
          speakerOn = true;
          break;
        case AudioDeviceType.earpiece:
          await Helper.setSpeakerphoneOn(false);
          speakerOn = false;
          break;
        case AudioDeviceType.bluetooth:
          await Helper.setSpeakerphoneOnButPreferBluetooth();
          speakerOn = false;
          break;
        default:
          break;
      }
      _selectedDevice = device;
    } catch (e) {
      Logs().e('[VOIP] Failed to set audio device: $device', e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState? state) {
    background =
        (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused);
  }

  /// Возвращает false если контекста нет — звонок кладётся в очередь
  /// и показывается при первом доступном контексте (тап по уведомлению,
  /// открытие списка чатов). Раньше тут был throw и оставалось только
  /// уведомление без окна — особенно заметно на видео-звонках из фона.
  bool tryAddCallingOverlay(String callId, CallSession call) {
    final context = this.context;
    if (context == null || !context.mounted) {
      Logs().w('[VOIP] No context for overlay, queue call $callId');
      _pendingCalls[callId] = call;
      return false;
    }

    if (overlayEntry != null) {
      Logs().e('[VOIP] addCallingOverlay: The call session already exists?');
      overlayEntry!.remove();
    }

    overlayEntry = OverlayEntry(
      builder: (_) => Calling(
        context: context,
        client: client,
        callId: callId,
        call: call,
        onClear: () {
          overlayEntry?.remove();
          overlayEntry = null;
        },
      ),
    );
    Overlay.of(context).insert(overlayEntry!);
    _pendingCalls.remove(callId);
    return true;
  }

  void addCallingOverlay(String callId, CallSession call) {
    tryAddCallingOverlay(callId, call);
  }

  /// Показать отложенные входящие (вызывается когда контекст появился).
  void flushPendingOverlays() {
    if (_pendingCalls.isEmpty) return;
    for (final entry in _pendingCalls.values.toList()) {
      if (entry.callHasEnded) {
        _pendingCalls.remove(entry.callId);
        continue;
      }
      if (overlayEntry != null) break;
      Logs().i('[VOIP] Flush pending call ${entry.callId}');
      if (!tryAddCallingOverlay(entry.callId, entry)) break;
    }
  }

  @override
  MediaDevices get mediaDevices => webrtc_impl.navigator.mediaDevices;

  @override
  bool get isWeb => kIsWeb;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) => webrtc_impl.createPeerConnection(configuration, constraints);

  Future<bool> get hasCallingAccount async => false;

  @override
  Future<void> playRingtone() async {
    // Звоним всегда, и в фоне тоже: на заблокированном экране иначе
    // тишина — звук канала galmax_call может не сработать (канал уже
    // закреплён системой без звука), а вибро вообще только через натив.
    if (!await hasCallingAccount) {
      try {
        // Use the new CallRingPlayer for system ringtone (like SchildiChat)
        await CallRingPlayer().startIncomingRing();
      } catch (_) {}
    }
  }

  @override
  Future<void> stopRingtone() async {
    if (!await hasCallingAccount) {
      try {
        await CallRingPlayer().stop();
      } catch (_) {}
    }
  }

  @override
  Future<void> handleNewCall(CallSession call) async {
    // Set default audio route based on call type (like Element Android)
    unawaited(setDefaultAudioRoute(call));

    // Start foreground service on Android to keep mic alive during calls
    if (PlatformInfos.isAndroid && _foregroundTaskInitialized) {
      try {
        final callerName = call.remoteUser?.calcDisplayname() ?? 'GAlMax';
        final callType = call.type == CallType.kVideo ? 'Video' : 'Voice';
        FlutterForegroundTask.startService(
          notificationTitle: '$callType call — $callerName',
          notificationText: 'Tap to return to call',
        );
      } catch (e) {
        Logs().e('[VOIP] Failed to start foreground service', e);
      }
    }

    // Handle incoming calls
    if (call.isRinging && !call.isOutgoing) {
      // Show notification for incoming calls in background
      if (PlatformInfos.isAndroid && !_notifiedCalls.contains(call.callId)) {
        _notifiedCalls.add(call.callId);
        try {
          final plugin = FlutterLocalNotificationsPlugin();
          final callerName = call.remoteUser?.calcDisplayname() ?? 'Unknown';
          final isVideoCall = call.type == CallType.kVideo;
          // Тап по телу уведомления открывает комнату (galmaxPushPayload),
          // дальше ChatList.flushPendingOverlays покажет окно звонка.
          // Без payload тап ничего не делал и оставалось только уведомление.
          final payload = '${client.clientName}|${call.room.id}|${call.callId}';
          await CallNotificationHelper.showIncomingCallNotification(
            plugin: plugin,
            callId: call.callId,
            callerName: callerName,
            roomName: call.room.name ?? call.room.id,
            isVideoCall: isVideoCall,
            payload: payload,
          );
        } catch (e) {
          Logs().e('[VOIP] Failed to show call notification', e);
        }

        try {
          final wasForeground = await FlutterForegroundTask.isAppOnForeground;

          await matrix.store.setString(
            'wasForeground',
            wasForeground == true ? 'true' : 'false',
          );
          FlutterForegroundTask.setOnLockScreenVisibility(true);
          FlutterForegroundTask.wakeUpScreen();
          FlutterForegroundTask.launchApp();
        } catch (e) {
          Logs().e('VOIP foreground failed $e');
        }
      }

      // Страховка: SDK может не дёрнуть playRingtone в фоне (локскрин) —
      // стартуем нативный звонок+вибро сами. Синглтон guard от дабла.
      try {
        await CallRingPlayer().startIncomingRing();
      } catch (_) {}
    }

    // Handle outgoing calls - play outgoing ring
    if (call.isOutgoing) {
      try {
        await CallRingPlayer().startOutgoingRing();
      } catch (e) {
        Logs().e('[VOIP] Failed to start outgoing ring', e);
      }
    }

    // Always show the call overlay for both incoming and outgoing calls.
    // Не бросаем исключение: из фона контекста может не быть, звонок уже
    // в очереди _pendingCalls и покажется через flushPendingOverlays.
    try {
      addCallingOverlay(call.callId, call);
    } catch (e) {
      Logs().w('[VOIP] Overlay deferred for ${call.callId}', e);
    }
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    _notifiedCalls.remove(session.callId);
    _pendingCalls.remove(session.callId);

    // Stop ring sounds
    try {
      await CallRingPlayer().stop();
    } catch (_) {}

    // Reset audio route to default
    try {
      await Helper.setSpeakerphoneOn(false);
      speakerOn = false;
      _selectedDevice = AudioDeviceType.unknown;
    } catch (_) {}

    // Cancel call notification
    if (PlatformInfos.isAndroid) {
      try {
        final plugin = FlutterLocalNotificationsPlugin();
        await CallNotificationHelper.cancelCallNotification(
          plugin: plugin,
          callId: session.callId,
        );
      } catch (_) {}
    }

    if (overlayEntry != null) {
      overlayEntry!.remove();
      overlayEntry = null;
      if (PlatformInfos.isAndroid) {
        FlutterForegroundTask.setOnLockScreenVisibility(false);
        FlutterForegroundTask.stopService();
      }
    }
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {
    // TODO: implement handleGroupCallEnded
  }

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    // TODO: implement handleNewGroupCall
    return;
  }

  @override
  // TODO: implement canHandleNewCall
  bool get canHandleNewCall =>
      voip.currentCID == null && voip.currentGroupCID == null;

  @override
  Future<void> handleMissedCall(CallSession session) async {
    // Show missed call notification
    if (PlatformInfos.isAndroid) {
      try {
        final plugin = FlutterLocalNotificationsPlugin();
        final callerName = session.remoteUser?.calcDisplayname() ?? 'Unknown';
        await CallNotificationHelper.showMissedCallNotification(
          plugin: plugin,
          callId: session.callId,
          callerName: callerName,
          roomName: session.room.name ?? session.room.id,
        );
      } catch (e) {
        Logs().e('[VOIP] Failed to show missed call notification', e);
      }
    }
    return;
  }

  @override
  // TODO: implement keyProvider
  EncryptionKeyProvider? get keyProvider {
    // TODO: Implement me
    return null;
  }

  @override
  Future<void> registerListeners(CallSession session) async {
    // Monitor call state changes for stability (like Element Android's WebRtcCallManager)
    session.onCallEventChanged.stream.listen(
      (event) {
        Logs().v('[VOIP] Call event: $event for ${session.callId}');
        if (event == CallStateChange.kError) {
          Logs().e('[VOIP] Call error: ${session.callId}');
          // Try to show error notification
          if (PlatformInfos.isAndroid) {
            try {
              final plugin = FlutterLocalNotificationsPlugin();
              CallNotificationHelper.showMissedCallNotification(
                plugin: plugin,
                callId: session.callId,
                callerName: 'Call failed',
                roomName: session.room.name ?? session.room.id,
              );
            } catch (_) {}
          }
        }
      },
      onError: (e) {
        Logs().e('[VOIP] Error in call event stream', e);
      },
    );
  }
}
