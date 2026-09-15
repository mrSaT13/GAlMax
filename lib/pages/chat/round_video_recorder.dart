// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:galmax/utils/galmax_activity.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:video_compress/video_compress.dart';
import 'package:camera/camera.dart';

class RoundVideoOverlay extends StatefulWidget {
  final Room room;
  final VoidCallback onClose;
  final String? threadRootEventId;
  final String? threadLastEventId;

  const RoundVideoOverlay({
    required this.room,
    required this.onClose,
    this.threadRootEventId,
    this.threadLastEventId,
    super.key,
  });

  @override
  State<RoundVideoOverlay> createState() => _RoundVideoOverlayState();
}

class _RoundVideoOverlayState extends State<RoundVideoOverlay>
    with TickerProviderStateMixin {
  bool _isRecording = false;
  bool _isProcessing = false;
  double _recordingProgress = 0;
  Timer? _progressTimer;
  late AnimationController _pulseController;
  late AnimationController _slideController;
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  List<CameraDescription> _cameras = [];
  CameraLensDirection _currentDirection = CameraLensDirection.front;

  static const int _maxDurationSeconds = 60;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _initCamera();
  }

  Future<void> _initCamera([
    CameraLensDirection? direction,
  ]) async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final wanted = direction ?? _currentDirection;
      final selected = _cameras.firstWhere(
        (c) => c.lensDirection == wanted,
        orElse: () => _cameras.first,
      );
      _currentDirection = selected.lensDirection;
      _cameraController = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _cameraInitialized = true);
      }
    } catch (e) {
      // Camera not available, show icon instead
    }
  }

  /// Switch front/back camera. Only before recording starts:
  /// the camera plugin cannot hot-swap lenses mid-recording.
  Future<void> _switchCamera() async {
    if (_isRecording || _isProcessing || _cameras.length < 2) return;
    final next = _currentDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    if (_cameras.every((c) => c.lensDirection != next)) return;
    setState(() => _cameraInitialized = false);
    await _cameraController?.dispose();
    _cameraController = null;
    await _initCamera(next);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    GalmaxActivity.stopActivity(widget.room);
    _pulseController.dispose();
    _slideController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      GalmaxActivity.send(widget.room, GalmaxActivity.recordingRound);
      setState(() {
        _isRecording = true;
        _recordingProgress = 0;
      });

      _progressTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (timer) {
          setState(() {
            _recordingProgress += 50 / (_maxDurationSeconds * 1000);
            if (_recordingProgress >= 1) {
              _stopRecording();
            }
          });
        },
      );
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _stopRecording() async {
    _progressTimer?.cancel();
    if (_cameraController == null || !_cameraController!.value.isRecordingVideo) {
      return;
    }

    try {
      final file = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });
      await _processAndSendVideo(file);
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
    }
  }

  Future<void> _processAndSendVideo(XFile videoFile) async {
    GalmaxActivity.send(widget.room, GalmaxActivity.uploadingVideo);
    try {
      final compressedInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      final fileToSend = compressedInfo?.file != null
          ? File(compressedInfo!.file!.path)
          : File(videoFile.path);

      final bytes = await fileToSend.readAsBytes();
      final fileName = 'round_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final matrixFile = MatrixVideoFile(
        bytes: bytes,
        name: fileName,
        mimeType: 'video/mp4',
      );

      final info = await VideoCompress.getMediaInfo(videoFile.path);

      await widget.room.sendFileEvent(
        matrixFile,
        threadRootEventId: widget.threadRootEventId,
        threadLastEventId: widget.threadLastEventId,
        extraContent: {
          'info': {
            ...matrixFile.info,
            'duration': info.duration,
          },
          'org.matrix.msc3245.round': {},
          'msgtype': 'm.video',
        },
      );
    } on MatrixException catch (e) {
      // Флуд-контроль сервера: одна попытка повтора после Retry-After.
      final retryAfterMs = e.retryAfterMs;
      if (e.error == MatrixError.M_LIMIT_EXCEEDED && retryAfterMs != null) {
        try {
          await Future.delayed(Duration(milliseconds: retryAfterMs + 1000));
          final bytes = await File(videoFile.path).readAsBytes();
          await widget.room.sendFileEvent(
            MatrixVideoFile(
              bytes: bytes,
              name:
                  'round_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
              mimeType: 'video/mp4',
            ),
            threadRootEventId: widget.threadRootEventId,
            threadLastEventId: widget.threadLastEventId,
          );
        } catch (_) {}
      }
    } catch (e) {
      // Handle error
    } finally {
      GalmaxActivity.stopActivity(widget.room);
    }

    if (mounted) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final circleSize = size.width * 0.7;

    return AnimatedBuilder(
      animation: _slideController,
      builder: (context, child) {
        return Opacity(
          opacity: _slideController.value,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              color: Colors.black54,
              child: Stack(
                children: [
                  // Circular camera preview + timer under the circle
                  Center(
                    child: Transform.scale(
                      scale: _slideController.value,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: circleSize,
                            height: circleSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isRecording
                                    ? Colors.red
                                    : Colors.white.withAlpha(150),
                                width: 4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(100),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _cameraInitialized &&
                                      _cameraController != null
                                  ? FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _cameraController!
                                            .value.previewSize!.height,
                                        height: _cameraController!
                                            .value.previewSize!.width,
                                        child: CameraPreview(
                                          _cameraController!,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[900],
                                      child: const Icon(
                                        Icons.videocam,
                                        size: 48,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Timer under the circle (Telegram-style)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isRecording)
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.red,
                                  ),
                                ),
                              if (_isRecording) const SizedBox(width: 8),
                              Text(
                                _isRecording
                                    ? _formatDuration(
                                        (_recordingProgress *
                                                _maxDurationSeconds)
                                            .toInt(),
                                      )
                                    : '00:00',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(
                                    _isRecording ? 255 : 150,
                                  ),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Close button
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 8,
                    left: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        widget.onClose();
                      },
                    ),
                  ),

                  // Record button
                  if (!_isProcessing)
                    Positioned(
                      bottom: MediaQuery.paddingOf(context).bottom + 40,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _isRecording ? _stopRecording : _startRecording,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording ? Colors.red : Colors.white,
                              border: Border.all(
                                color: Colors.white,
                                width: 4,
                              ),
                            ),
                            child: _isProcessing
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  )
                                : Icon(
                                    _isRecording ? Icons.stop : Icons.circle,
                                    color: _isRecording ? Colors.white : Colors.red,
                                    size: 40,
                                  ),
                          ),
                        ),
                      ),
                    ),

                  // Flip camera button (switches lens before recording)
                  if (_cameraInitialized && !_isProcessing)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 8,
                      right: 16,
                      child: IconButton(
                        tooltip: 'Switch camera',
                        icon: Icon(
                          Icons.flip_camera_ios_outlined,
                          color: _isRecording
                              ? Colors.white.withAlpha(100)
                              : Colors.white,
                        ),
                        onPressed: _isRecording ? null : _switchCamera,
                      ),
                    ),

                  // Progress ring around circle
                  if (_isRecording)
                    Center(
                      child: SizedBox(
                        width: circleSize + 16,
                        height: circleSize + 16,
                        child: CustomPaint(
                          painter: _ProgressRingPainter(
                            progress: _recordingProgress,
                          ),
                        ),
                      ),
                    ),

                  // Processing indicator
                  if (_isProcessing)
                    Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;

  _ProgressRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background ring
    final bgPaint = Paint()
      ..color = Colors.white.withAlpha(50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress ring
    final progressPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
