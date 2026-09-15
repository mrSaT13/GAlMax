// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Sound player for incoming/outgoing calls
/// Mirrors SchildiChat's CallRingPlayer behavior:
/// - Incoming: system ringtone via RingtoneManager (Android) or just_audio (iOS)
/// - Outgoing: custom ring.ogg file
/// - Vibration handled natively via MethodChannel
class CallRingPlayer {
  static const _channel = MethodChannel('im.galmax.app/call_ring');

  AudioPlayer? _ringtonePlayer;
  AudioPlayer? _outgoingPlayer;
  bool _isRinging = false;
  bool _isOutgoing = false;

  static final CallRingPlayer _instance = CallRingPlayer._internal();
  factory CallRingPlayer() => _instance;
  CallRingPlayer._internal();

  bool get isRinging => _isRinging;
  bool get isOutgoing => _isOutgoing;

  /// Start playing ring tone for incoming call
  /// Uses system ringtone on Android (like SchildiChat)
  Future<void> startIncomingRing() async {
    if (_isRinging) return;
    _isRinging = true;
    _isOutgoing = false;

    try {
      // Try to use system ringtone via native code (Android)
      final result = await _channel.invokeMethod<bool>('startIncomingRing');
      if (result == true) {
        // Native ring started successfully (includes vibration)
        return;
      }
    } catch (_) {
      // Native not available, fall through to Flutter audio
    }

    // Fallback: use Flutter audio player
    await _startFlutterIncomingRing();
  }

  /// Start playing ring tone for outgoing call
  /// Uses custom ring.ogg file (like SchildiChat)
  Future<void> startOutgoingRing() async {
    if (_isOutgoing) return;
    _isOutgoing = true;
    _isRinging = false;

    try {
      // Try native outgoing ring first
      final result = await _channel.invokeMethod<bool>('startOutgoingRing');
      if (result == true) return;
    } catch (_) {}

    // Fallback: use Flutter audio player with ring.ogg
    await _startFlutterOutgoingRing();
  }

  /// Stop all ringing sounds
  Future<void> stop() async {
    _isRinging = false;
    _isOutgoing = false;

    // Stop native ring
    try {
      await _channel.invokeMethod('stopRing');
    } catch (_) {}

    // Stop Flutter audio players
    await _ringtonePlayer?.stop();
    _ringtonePlayer?.dispose();
    _ringtonePlayer = null;

    await _outgoingPlayer?.stop();
    _outgoingPlayer?.dispose();
    _outgoingPlayer = null;
  }

  Future<void> _startFlutterIncomingRing() async {
    try {
      _ringtonePlayer = AudioPlayer();
      await _ringtonePlayer!.setAsset('assets/sounds/phone.ogg');
      await _ringtonePlayer!.setLoopMode(LoopMode.one);
      await _ringtonePlayer!.play();
    } catch (e) {
      try {
        _ringtonePlayer = AudioPlayer();
        await _ringtonePlayer!.setAsset('assets/sounds/call.ogg');
        await _ringtonePlayer!.setLoopMode(LoopMode.one);
        await _ringtonePlayer!.play();
      } catch (_) {}
    }
  }

  Future<void> _startFlutterOutgoingRing() async {
    try {
      _outgoingPlayer = AudioPlayer();
      await _outgoingPlayer!.setAsset('assets/sounds/call.ogg');
      await _outgoingPlayer!.setLoopMode(LoopMode.one);
      await _outgoingPlayer!.play();
    } catch (_) {}
  }
}
