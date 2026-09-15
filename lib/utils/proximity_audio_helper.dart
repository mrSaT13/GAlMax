// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';

/// Proximity sensor manager.
/// - For VOICE MESSAGES: switches earpiece/speaker based on proximity
/// - For VOIP CALLS: only handles screen on/off (via native PROXIMITY_SCREEN_OFF_WAKE_LOCK)
class ProximityAudioHelper {
  static ProximityAudioHelper? _instance;
  static ProximityAudioHelper get instance => _instance ??= ProximityAudioHelper._();
  ProximityAudioHelper._();

  bool _isActive = false;
  bool _isForCall = false;
  MethodChannel? _platform;

  bool get isActive => _isActive;
  bool get isForCall => _isForCall;

  final StreamController<bool> _proximityController = StreamController<bool>.broadcast();
  Stream<bool> get proximityStream => _proximityController.stream;

  // Overlay callbacks for voice messages (block touches when phone at ear)
  VoidCallback? _showProximityOverlay;
  VoidCallback? _hideProximityOverlay;

  void setOverlayCallbacks({
    VoidCallback? onShow,
    VoidCallback? onHide,
  }) {
    _showProximityOverlay = onShow;
    _hideProximityOverlay = onHide;
  }

  /// Start proximity listening.
  /// [forCall] = true: only screen on/off (no audio route changes)
  /// [forCall] = false: earpiece/speaker switching for voice messages
  Future<void> startListening({bool forCall = false}) async {
    if (_isActive) return;
    _isActive = true;
    _isForCall = forCall;

    try {
      _platform = const MethodChannel('galmax/proximity');
      await _platform!.invokeMethod('startProximity');
      _platform!.setMethodCallHandler((call) async {
        if (call.method == 'proximityChanged') {
          final bool isNear = call.arguments as bool;
          _proximityController.add(isNear);

          // For calls: screen on/off is handled natively via PROXIMITY_SCREEN_OFF_WAKE_LOCK
          // For voice messages: switch audio route
          if (!_isForCall) {
            await _handleVoiceMessageProximity(isNear);
          }
        }
      });
    } catch (_) {}
  }

  /// Handle proximity for voice messages — switch between earpiece and speaker
  Future<void> _handleVoiceMessageProximity(bool nearEar) async {
    try {
      if (nearEar) {
        // Switch to earpiece
        await _platform?.invokeMethod('setAudioRoute', 'earpiece');
        // Show black overlay to block touches
        _showProximityOverlay?.call();
      } else {
        // Switch back to speaker
        await _platform?.invokeMethod('setAudioRoute', 'speaker');
        // Hide black overlay
        _hideProximityOverlay?.call();
      }
    } catch (_) {}
  }

  Future<void> onPlaybackStarted() async {
    if (!_isActive) await startListening(forCall: false);
  }

  Future<void> onPlaybackStopped() async {
    // Reset audio route to normal
    try {
      await _platform?.invokeMethod('setAudioRoute', 'normal');
    } catch (_) {}
    if (_isActive) await stopListening();
  }

  /// Start proximity for a call (screen only, no audio route changes)
  Future<void> startCallProximity() async {
    await startListening(forCall: true);
  }

  /// Stop proximity for a call
  Future<void> stopCallProximity() async {
    if (_isForCall) {
      await stopListening();
    }
  }

  Future<void> stopListening() async {
    _isActive = false;
    _isForCall = false;

    try {
      await _platform?.invokeMethod('stopProximity');
    } catch (_) {}
  }

  void dispose() {
    _proximityController.close();
  }
}
