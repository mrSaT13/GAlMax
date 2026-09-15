// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:galmax/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class CircularVideoPlayer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final double size;
  final bool autoPlay;
  final bool showProgress;
  final VoidCallback? onTap;

  const CircularVideoPlayer({
    required this.event,
    this.timeline,
    this.size = 240,
    this.autoPlay = false,
    this.showProgress = true,
    this.onTap,
    super.key,
  });

  @override
  CircularVideoPlayerState createState() => CircularVideoPlayerState();
}

class CircularVideoPlayerState extends State<CircularVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isDownloaded = false;
  String? _videoPath;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    // Check if video is already downloaded
    try {
      final matrixFile = await widget.event.downloadAndDecryptAttachment();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${matrixFile.name}');
      await tempFile.writeAsBytes(matrixFile.bytes);
      _videoPath = tempFile.path;
      _isDownloaded = true;
      await _initializeController();
    } catch (e) {
      // Video not downloaded yet, show placeholder
      setState(() {});
    }
  }

  Future<void> _initializeController() async {
    if (_videoPath == null) return;

    try {
      _controller = VideoPlayerController.file(File(_videoPath!));
      await _controller!.initialize();
      await _controller!.setLooping(true);

      if (widget.autoPlay) {
        _controller!.play();
        _isPlaying = true;
      }

      setState(() {
        _isInitialized = true;
      });

      // Listen for video completion
      _controller!.addListener(() {
        if (mounted) {
          setState(() {
            _isPlaying = _controller!.value.isPlaying;
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  void _togglePlayPause() {
    if (_controller == null) {
      // If not downloaded, try to download first
      widget.event.saveFile(context);
      return;
    }

    setState(() {
      if (_isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final infoMap = widget.event.content.tryGetMap<String, Object?>('info');
    final durationMs = infoMap?.tryGet<int>('duration');
    final duration = durationMs != null
        ? Duration(milliseconds: durationMs)
        : Duration.zero;

    return GestureDetector(
      onTap: _isDownloaded
          ? _togglePlayPause
          : () => widget.event.saveFile(context),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size / 2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video or thumbnail — scaled to fill circle (cover mode)
              if (_isInitialized &&
                  _controller != null &&
                  _controller!.value.isInitialized)
                Center(
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),
                )
              else
                _buildThumbnail(context),

              // Progress overlay (when not playing and showing progress)
              if (widget.showProgress &&
                  !_isPlaying &&
                  _isInitialized &&
                  _controller != null)
                _buildProgressOverlay(duration),

              // Play button overlay (when paused or not downloaded)
              if (!_isPlaying || !_isInitialized)
                _buildPlayOverlay(theme),

              // Duration text
              if (duration > Duration.zero)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(128),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    // Use thumbnail from event or placeholder
    if (widget.event.hasThumbnail) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(
                child: Icon(
                  Icons.videocam,
                  size: 48,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(
          Icons.videocam,
          size: 48,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildProgressOverlay(Duration totalDuration) {
    if (_controller == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withAlpha(77),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayOverlay(ThemeData theme) {
    final canPlay = _isDownloaded && _isInitialized;

    return Container(
      color: Colors.black.withAlpha(77),
      child: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: canPlay
                ? theme.colorScheme.primary
                : Colors.black.withAlpha(128),
          ),
          child: Icon(
            canPlay ? Icons.play_arrow : Icons.download,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }
}

// Simple video note bubble for chat display
class VideoNoteBubble extends StatelessWidget {
  final Event event;
  final Timeline? timeline;
  final VoidCallback? onTap;

  const VideoNoteBubble({
    required this.event,
    this.timeline,
    this.onTap,
    super.key,
  });

  static const double defaultSize = 240.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => _showExpandedCircle(context),
      child: CircularVideoPlayer(
        event: event,
        timeline: timeline,
        size: defaultSize,
        autoPlay: false,
        showProgress: true,
      ),
    );
  }

  /// Telegram-style: tap expands the circle to (almost) screen width.
  void _showExpandedCircle(BuildContext context) async {
    if (!PlatformInfos.supportsVideoPlayer) {
      event.saveFile(context);
      return;
    }
    try {
      final matrixFile = await event.downloadAndDecryptAttachment();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${matrixFile.name}');
      await tempFile.writeAsBytes(matrixFile.bytes);
      if (!context.mounted) return;
      await showGeneralDialog(
        context: context,
        barrierColor: Colors.black.withAlpha(230),
        barrierDismissible: true,
        barrierLabel: 'Close',
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, _, __) => _ExpandedCircleViewer(
          videoPath: tempFile.path,
        ),
        transitionBuilder: (context, animation, _, child) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: child,
        ),
      );
    } catch (e) {
      event.saveFile(context);
      return;
    }
  }
}

/// Expanded Telegram-style circle viewer: video plays in a big circle
/// sized to (almost) the screen width. Tap anywhere to close.
class _ExpandedCircleViewer extends StatefulWidget {
  final String videoPath;

  const _ExpandedCircleViewer({required this.videoPath});

  @override
  State<_ExpandedCircleViewer> createState() => _ExpandedCircleViewerState();
}

class _ExpandedCircleViewerState extends State<_ExpandedCircleViewer> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _controller = VideoPlayerController.file(File(widget.videoPath));
      await _controller!.initialize();
      await _controller!.setLooping(true);
      await _controller!.play();
      if (mounted) setState(() => _ready = true);
      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (_) {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final circleSize = width * 0.92;
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: ClipOval(
                  child: _ready && _controller != null
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white24,
                  ),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullScreenVideoPlayer extends StatefulWidget {
  final String videoPath;
  final Event event;

  const _FullScreenVideoPlayer({
    required this.videoPath,
    required this.event,
  });

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  Future<void> _initializeController() async {
    _controller = VideoPlayerController.file(File(widget.videoPath));
    await _controller.initialize();
    await _controller.play();

    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Dialog(
        backgroundColor: Colors.black,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.black,
      child: GestureDetector(
        onTap: () {
          if (_controller.value.isPlaying) {
            _controller.pause();
          } else {
            _controller.play();
          }
          setState(() {});
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
