// Copyright (C) 2019-2021 Famedly GmbH
// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/call_ring_player.dart';
import 'package:galmax/utils/string_color.dart';
import 'package:galmax/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/utils/proximity_audio_helper.dart';
import 'package:galmax/utils/voip/video_renderer.dart';
import 'package:galmax/widgets/avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide VideoRenderer;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'pip/pip_view.dart';

class _StreamView extends StatelessWidget {
  const _StreamView(
    this.wrappedStream, {
    this.mainView = false,
    required this.matrixClient,
  });

  final WrappedMediaStream wrappedStream;
  final Client matrixClient;

  final bool mainView;

  Uri? get avatarUrl => wrappedStream.getUser().avatarUrl;

  String? get displayName => wrappedStream.displayName;

  String get avatarName => wrappedStream.avatarName;

  bool get isLocal => wrappedStream.isLocal();

  bool get mirrored =>
      wrappedStream.isLocal() &&
      wrappedStream.purpose == SDPStreamMetadataPurpose.Usermedia;

  bool get audioMuted => wrappedStream.audioMuted;

  bool get videoMuted => wrappedStream.videoMuted;

  bool get isScreenSharing =>
      wrappedStream.purpose == SDPStreamMetadataPurpose.Screenshare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.black54),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          VideoRenderer(
            wrappedStream,
            mirror: mirrored,
            fit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
          if (videoMuted) ...[
            Container(color: Colors.black54),
            Positioned(
              child: Avatar(
                mxContent: avatarUrl,
                name: displayName,
                size: mainView ? 96 : 48,
                client: matrixClient,
              ),
            ),
          ],
          if (!isScreenSharing)
            Positioned(
              left: 4.0,
              bottom: 4.0,
              child: Icon(
                audioMuted ? Icons.mic_off : Icons.mic,
                color: Colors.white,
                size: 18.0,
              ),
            ),
        ],
      ),
    );
  }
}

class Calling extends StatefulWidget {
  final VoidCallback? onClear;
  final BuildContext context;
  final String callId;
  final CallSession call;
  final Client client;

  const Calling({
    required this.context,
    required this.call,
    required this.client,
    required this.callId,
    this.onClear,
    super.key,
  });

  @override
  MyCallingPage createState() => MyCallingPage();
}

class MyCallingPage extends State<Calling> with TickerProviderStateMixin {
  Room? get room => call.room;

  String get displayName =>
      call.room.getLocalizedDisplayname(MatrixLocals(L10n.of(widget.context)));

  String get callId => widget.callId;

  CallSession get call => widget.call;

  MediaStream? get localStream {
    if (call.localUserMediaStream != null) {
      return call.localUserMediaStream!.stream!;
    }
    return null;
  }

  MediaStream? get remoteStream {
    if (call.getRemoteStreams.isNotEmpty) {
      return call.getRemoteStreams.first.stream!;
    }
    return null;
  }

  bool get isMicrophoneMuted => call.isMicrophoneMuted;

  bool get isLocalVideoMuted => call.isLocalVideoMuted;

  bool get isScreensharingEnabled => call.screensharingEnabled;

  bool get isRemoteOnHold => call.remoteOnHold;

  bool get voiceonly => call.type == CallType.kVoice;

  bool get connecting => call.state == CallState.kConnecting;

  bool get connected => call.state == CallState.kConnected;

  double? _localVideoHeight;
  double? _localVideoWidth;
  EdgeInsetsGeometry? _localVideoMargin;
  CallState? _state;

  // Audio device state (like Element Android)
  bool _isSpeakerOn = false;

  // Call duration timer
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String get _callStatusText {
    switch (_state) {
      case CallState.kRinging:
        return call.isOutgoing ? 'Вызов...' : 'Входящий звонок...';
      case CallState.kInviteSent:
        return 'Вызов...';
      case CallState.kConnecting:
        return 'Подключение...';
      case CallState.kConnected:
        final m = _callDuration.inMinutes;
        final s = (_callDuration.inSeconds % 60);
        return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      case CallState.kEnded:
        return 'Звонок завершён';
      default:
        return '';
    }
  }

  Future<void> _playCallSound() async {
    // Only play ringtone for INCOMING calls, not outgoing
    if (call.isOutgoing) return;

    // Use the new CallRingPlayer for system ringtone (like SchildiChat)
    try {
      await CallRingPlayer().startIncomingRing();
    } catch (e) {
      Logs().w('Failed to start incoming ring: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    initialize();
    _playCallSound();
  }

  void initialize() {
    final call = this.call;
    call.onCallStateChanged.stream.listen(_handleCallState);
    call.onCallEventChanged.stream.listen((event) {
      if (event == CallStateChange.kFeedsChanged) {
        setState(call.tryRemoveStopedStreams);
      } else if (event == CallStateChange.kLocalHoldUnhold ||
          event == CallStateChange.kRemoteHoldUnhold) {
        setState(() {});
        Logs().i(
          'Call hold event: local ${call.localHold}, remote ${call.remoteOnHold}',
        );
      }
    });
    _state = call.state;

    if (call.type == CallType.kVideo) {
      try {
        unawaited(WakelockPlus.enable());
      } catch (_) {}
    }
  }

  void cleanUp() {
    _pulseController.dispose();
    Timer(const Duration(seconds: 2), () => widget.onClear?.call());
    if (call.type == CallType.kVideo) {
      try {
        unawaited(WakelockPlus.disable());
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    ProximityAudioHelper.instance.onPlaybackStopped();
    _pulseController.dispose();
    super.dispose();
    call.cleanUp.call();
  }

  void _resizeLocalVideo(Orientation orientation) {
    final shortSide = min(
      MediaQuery.sizeOf(widget.context).width,
      MediaQuery.sizeOf(widget.context).height,
    );
    _localVideoMargin = remoteStream != null
        ? const EdgeInsets.only(top: 20.0, right: 20.0)
        : EdgeInsets.zero;
    _localVideoWidth = remoteStream != null
        ? shortSide / 3
        : MediaQuery.sizeOf(widget.context).width;
    _localVideoHeight = remoteStream != null
        ? shortSide / 4
        : MediaQuery.sizeOf(widget.context).height;
  }

  void _handleCallState(CallState state) {
    Logs().v('CallingPage::handleCallState: $state');
    if ({CallState.kConnected, CallState.kEnded}.contains(state)) {
      HapticFeedback.heavyImpact();
    }

    // Proximity sensor for calls: screen on/off only (no audio route changes)
    // Audio routing during calls is managed by WebRTC, NOT by proximity
    if (state == CallState.kConnected && voiceonly) {
      ProximityAudioHelper.instance.startCallProximity();
    }
    // Start call duration timer when connected
    if (state == CallState.kConnected) {
      _callDuration = Duration.zero;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _callDuration += const Duration(seconds: 1);
          });
        }
      });
    }
    if (state == CallState.kEnded) {
      _durationTimer?.cancel();
      ProximityAudioHelper.instance.stopCallProximity();
    }

    if (mounted) {
      setState(() {
        _state = state;
        if (_state == CallState.kEnded) cleanUp();
      });
    }
  }

  void _answerCall() {
    // Stop ring sounds when answering
    CallRingPlayer().stop();
    setState(() {
      call.answer();
    });
  }

  void _hangUp() {
    // Stop ring sounds when hanging up
    CallRingPlayer().stop();
    setState(() {
      if (call.isRinging) {
        call.reject();
      } else {
        call.hangup(reason: CallErrorCode.userHangup);
      }
    });
  }

  void _muteMic() {
    setState(() {
      call.setMicrophoneMuted(!call.isMicrophoneMuted);
    });
  }

  void _screenSharing() {
    if (PlatformInfos.isAndroid) {
      if (!call.screensharingEnabled) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'notification_channel_id',
            channelName: 'Foreground Notification',
            channelDescription: L10n.of(
              widget.context,
            ).foregroundServiceRunning,
          ),
          iosNotificationOptions: const IOSNotificationOptions(),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
          ),
        );
        FlutterForegroundTask.startService(
          notificationTitle: L10n.of(widget.context).screenSharingTitle,
          notificationText: L10n.of(widget.context).screenSharingDetail,
        );
      } else {
        FlutterForegroundTask.stopService();
      }
    }

    setState(() {
      call.setScreensharingEnabled(!call.screensharingEnabled);
    });
  }

  void _remoteOnHold() {
    setState(() {
      call.setRemoteOnHold(!call.remoteOnHold);
    });
  }

  void _muteCamera() {
    setState(() {
      call.setLocalVideoMuted(!call.isLocalVideoMuted);
    });
  }

  Future<void> _toggleSpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(!_isSpeakerOn);
      setState(() {
        _isSpeakerOn = !_isSpeakerOn;
      });
    } catch (e) {
      Logs().e('[CallUI] Failed to toggle speaker', e);
    }
  }

  Future<void> _switchCamera() async {
    if (call.localUserMediaStream != null) {
      await Helper.switchCamera(
        call.localUserMediaStream!.stream!.getVideoTracks().first,
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    // Акцент фона — из цвета аватара собеседника (тот же что в кружке
    // без фото), дальше тот же тёмный градиент что был.
    final accent = (call.remoteUser?.calcDisplayname() ?? displayName)
        .lightColorAvatar;

    return PIPView(
      builder: (context, isFloating) {
        // Icon-only buttons (like Element Android) — no labels
        final hangupButton = _CallActionButton(
          icon: Icons.call_end,
          onTap: _hangUp,
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        );
        final answerButton = _CallActionButton(
          icon: Icons.phone,
          onTap: _answerCall,
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        );
        final muteMicButton = _CallActionButton(
          icon: isMicrophoneMuted ? Icons.mic_off : Icons.mic,
          onTap: _muteMic,
          isActive: isMicrophoneMuted,
        );
        final speakerButton = _CallActionButton(
          icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
          onTap: _toggleSpeaker,
          isActive: _isSpeakerOn,
        );
        final muteCameraButton = _CallActionButton(
          icon: isLocalVideoMuted ? Icons.videocam_off : Icons.videocam,
          onTap: _muteCamera,
          isActive: isLocalVideoMuted,
        );

        // Overflow menu button (3 dots) — holds secondary actions
        final moreButton = _PopupMenuButton(
          items: [
            _PopupMenuItem(
              icon: Icons.pause,
              label: isRemoteOnHold ? 'Снять удержание' : 'Удержание',
              onTap: _remoteOnHold,
              isActive: isRemoteOnHold,
            ),
            if (!kIsWeb)
              _PopupMenuItem(
                icon: Icons.switch_camera,
                label: 'Перевернуть камеру',
                onTap: _switchCamera,
              ),
            _PopupMenuItem(
              icon: Icons.screen_share_outlined,
              label: isScreensharingEnabled ? 'Остановить демонстрацию' : 'Демонстрация экрана',
              onTap: _screenSharing,
              isActive: isScreensharingEnabled,
            ),
          ],
        );

        late final List<Widget> actionButtons;
        if (!isFloating) {
          switch (_state) {
            case CallState.kRinging:
            case CallState.kInviteSent:
            case CallState.kCreateAnswer:
            case CallState.kConnecting:
              actionButtons = call.isOutgoing
                  ? <Widget>[hangupButton]
                  : <Widget>[answerButton, hangupButton];
              break;
            case CallState.kConnected:
              if (voiceonly) {
                // Voice call: mic, speaker, more, hangup
                actionButtons = <Widget>[
                  muteMicButton,
                  if (!kIsWeb) speakerButton,
                  moreButton,
                  hangupButton,
                ];
              } else {
                // Video call: mic, camera, more, hangup
                actionButtons = <Widget>[
                  muteMicButton,
                  muteCameraButton,
                  moreButton,
                  hangupButton,
                ];
              }
              break;
            case CallState.kEnded:
              actionButtons = <Widget>[hangupButton];
              break;
            case CallState.kFledgling:
            case CallState.kWaitLocalMedia:
            case CallState.kCreateOffer:
            case CallState.kEnding:
            case null:
              actionButtons = <Widget>[];
              break;
          }
        } else {
          actionButtons = <Widget>[];
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: !isFloating,
          body: OrientationBuilder(
            builder: (BuildContext context, Orientation orientation) {
              final stackWidgets = <Widget>[];

              final callHasEnded = call.callHasEnded;
              if (!callHasEnded) {
                if (call.localHold || call.remoteOnHold) {
                  var title = '';
                  if (call.localHold) {
                    title = 'Звонок удержан';
                  } else if (call.remoteOnHold) {
                    title = 'Вы удерживаете звонок';
                  }
                  stackWidgets.add(
                    Center(
                      child: Column(
                        mainAxisAlignment: .center,
                        children: [
                          const Icon(
                            Icons.pause,
                            size: 48.0,
                            color: Colors.white,
                          ),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  // Primary stream: remote video, local screen share, or remote camera
                  var primaryStream =
                      call.remoteScreenSharingStream ??
                      call.localScreenSharingStream ??
                      call.remoteUserMediaStream;

                  // Fallback: check getRemoteStreams if primary is null
                  if (primaryStream == null && call.getRemoteStreams.isNotEmpty) {
                    primaryStream = call.getRemoteStreams.first;
                  }

                  if (primaryStream != null) {
                    stackWidgets.add(
                      Center(
                        child: _StreamView(
                          primaryStream,
                          mainView: true,
                          matrixClient: widget.client,
                        ),
                      ),
                    );
                  } else {
                    stackWidgets.add(
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Animated pulse ring around avatar
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: primaryColor.withOpacity(
                                        0.3 * _pulseAnimation.value,
                                      ),
                                      width: 3,
                                    ),
                                  ),
                                  child: child,
                                );
                              },
                              child: Avatar(
                                size: 120,
                                name: call.remoteUser?.calcDisplayname() ?? displayName,
                                mxContent: call.remoteUser?.avatarUrl,
                                client: widget.client,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              call.remoteUser?.calcDisplayname() ?? displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _callStatusText,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (!isFloating && connected) {
                    _resizeLocalVideo(orientation);

                    if (call.getRemoteStreams.isNotEmpty) {
                      final secondaryStreamViews = <Widget>[];

                      if (call.remoteScreenSharingStream != null) {
                        final remoteUserMediaStream =
                            call.remoteUserMediaStream;
                        secondaryStreamViews.add(
                          SizedBox(
                            width: _localVideoWidth,
                            height: _localVideoHeight,
                            child: _StreamView(
                              remoteUserMediaStream!,
                              matrixClient: widget.client,
                            ),
                          ),
                        );
                        secondaryStreamViews.add(const SizedBox(height: 10));
                      }

                      final localStream =
                          call.localUserMediaStream ??
                          call.localScreenSharingStream;
                      // Don't show local video for voice-only calls
                      if (localStream != null && !isFloating && !voiceonly) {
                        secondaryStreamViews.add(
                          SizedBox(
                            width: _localVideoWidth,
                            height: _localVideoHeight,
                            child: _StreamView(
                              localStream,
                              matrixClient: widget.client,
                            ),
                          ),
                        );
                        secondaryStreamViews.add(const SizedBox(height: 10));
                      }

                      if (secondaryStreamViews.isNotEmpty) {
                        stackWidgets.add(
                          Container(
                            padding: const EdgeInsets.only(
                              top: 20,
                              bottom: 120,
                            ),
                            alignment: Alignment.bottomRight,
                            child: Container(
                              width: _localVideoWidth,
                              margin: _localVideoMargin,
                              child: Column(children: secondaryStreamViews),
                            ),
                          ),
                        );
                      }
                    }
                  }
                }
              }

              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accent.withOpacity(0.55),
                      const Color(0xFF0A0F1A),
                      const Color(0xFF050810),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: Stack(
                  children: [
                    ...stackWidgets,
                    if (!isFloating) ...[
                      // Top bar: back button + caller info
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            IconButton(
                              color: Colors.white70,
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () {
                                PIPView.of(context)?.setFloating(true);
                              },
                            ),
                            const Spacer(),
                            if (connected)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.greenAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _callStatusText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Bottom action buttons
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: MediaQuery.of(context).padding.bottom + 24,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: actionButtons,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isActive;

  const _CallActionButton({
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? Colors.white.withOpacity(0.15);
    final fgColor = foregroundColor ?? Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? Colors.white.withOpacity(0.25) : bgColor,
          border: isActive
              ? Border.all(color: Colors.white.withOpacity(0.4), width: 1.5)
              : null,
        ),
        child: Icon(icon, color: fgColor, size: 26),
      ),
    );
  }
}

class _PopupMenuButton extends StatelessWidget {
  final List<_PopupMenuItem> items;

  const _PopupMenuButton({required this.items});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: items.map((item) => ListTile(
                leading: Icon(
                  item.icon,
                  color: item.isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(item.label),
                onTap: () {
                  Navigator.pop(context);
                  item.onTap();
                },
              )).toList(),
            ),
          ),
        );
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.15),
        ),
        child: const Icon(Icons.more_vert, color: Colors.white, size: 26),
      ),
    );
  }
}

class _PopupMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _PopupMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });
}
