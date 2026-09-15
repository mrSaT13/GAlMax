// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:math';

import 'package:chewie/chewie.dart';
import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/utils/error_reporter.dart';
import 'package:galmax/utils/file_description.dart';
import 'package:galmax/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/utils/url_launcher.dart';
import 'package:galmax/widgets/blur_hash.dart';
import 'package:galmax/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

import '../../image_viewer/image_viewer.dart';

class EventVideoPlayer extends StatelessWidget {
  final Event event;
  final Timeline? timeline;
  final Color? textColor;
  final Color? linkColor;
  final bool forceSquare;

  const EventVideoPlayer(
    this.event, {
    this.timeline,
    this.textColor,
    this.linkColor,
    this.forceSquare = false,
    super.key,
  });

  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  bool get isRoundVideo {
    final content = event.content;
    return content.containsKey('org.matrix.msc3245.round');
  }

  @override
  Widget build(BuildContext context) {
    // Round videos play inline (but not in gallery/search)
    if (isRoundVideo && !forceSquare) {
      return _RoundVideoPlayer(
        event: event,
        textColor: textColor,
        linkColor: linkColor,
      );
    }

    // Regular videos open in viewer
    final supportsVideoPlayer = PlatformInfos.supportsVideoPlayer;

    final blurHash =
        (event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    final fileDescription = event.fileDescription;
    const maxDimension = 300.0;
    final infoMap = event.content.tryGetMap<String, Object?>('info');
    final videoWidth = infoMap?.tryGet<int>('w') ?? maxDimension;
    final videoHeight = infoMap?.tryGet<int>('h') ?? maxDimension;

    final modifier = max(videoWidth, videoHeight) / maxDimension;
    final width = videoWidth / modifier;
    final height = videoHeight / modifier;

    final durationInt = infoMap?.tryGet<int>('duration');
    final duration = durationInt == null
        ? null
        : Duration(milliseconds: durationInt);

    return Column(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        Material(
          color: Colors.black,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          child: InkWell(
            onTap: () => supportsVideoPlayer
                ? showDialog(
                    context: context,
                    builder: (_) => ImageViewer(
                      event,
                      timeline: timeline,
                      outerContext: context,
                    ),
                  )
                : event.saveFile(context),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            child: SizedBox(
              width: width,
              height: height,
              child: Hero(
                tag: event.eventId,
                child: Stack(
                  children: [
                    if (event.hasThumbnail &&
                        AppSettings.showThumbnailsInTimeline.value)
                      MxcImage(
                        event: event,
                        cacheKey: event.transactionId ?? event.eventId,
                        cacheName: event.room.id,
                        isThumbnail: true,
                        width: width,
                        height: height,
                        fit: BoxFit.cover,
                        placeholder: (context) => BlurHash(
                          blurhash: blurHash,
                          width: width,
                          height: height,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      BlurHash(
                        blurhash: blurHash,
                        width: width,
                        height: height,
                        fit: BoxFit.cover,
                      ),
                    Center(
                      child: CircleAvatar(
                        child: supportsVideoPlayer
                            ? const Icon(Icons.play_arrow_outlined)
                            : const Icon(Icons.file_download_outlined),
                      ),
                    ),
                    if (duration != null)
                      Positioned(
                        bottom: 8,
                        left: 16,
                        child: Text(
                          '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black.withAlpha(32),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (fileDescription != null && textColor != null && linkColor != null)
          SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Linkify(
                text: fileDescription,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                style: TextStyle(
                  color: textColor,
                  fontSize: AppConfig.messageFontSize,
                ),
                options: const LinkifyOptions(humanize: false),
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize: AppConfig.messageFontSize,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
              ),
            ),
          ),
      ],
    );
  }
}

/// Inline player for round videos — plays like a voice message with circular frame
class _RoundVideoPlayer extends StatefulWidget {
  final Event event;
  final Color? textColor;
  final Color? linkColor;

  const _RoundVideoPlayer({
    required this.event,
    this.textColor,
    this.linkColor,
  });

  @override
  State<_RoundVideoPlayer> createState() => _RoundVideoPlayerState();
}

class _RoundVideoPlayerState extends State<_RoundVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _hasError = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool get _supportsVideoPlayer =>
      !PlatformInfos.isWindows && !PlatformInfos.isLinux;

  @override
  void initState() {
    super.initState();
    _duration = _getDuration();
  }

  Duration _getDuration() {
    final infoMap = widget.event.content.tryGetMap<String, Object?>('info');
    final durationMs = infoMap?.tryGet<int>('duration');
    return durationMs != null ? Duration(milliseconds: durationMs) : Duration.zero;
  }

  Future<void> _loadAndPlay() async {
    if (_isLoading || _videoController != null) return;
    setState(() => _isLoading = true);

    try {
      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      final file = await widget.event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize == null
            ? null
            : (progress) {
                // Progress tracking
              },
      );

      if (!mounted) return;

      // Write to temporary file for video_player
      final tempDir = await Directory.systemTemp.createTemp('round_video');
      final tempFile = File('${tempDir.path}/video.mp4');
      await tempFile.writeAsBytes(file.bytes);

      _videoController = VideoPlayerController.file(tempFile);
      await _videoController!.initialize();

      _duration = _videoController!.value.duration;

      _videoController!.addListener(() {
        if (mounted) {
          setState(() {
            _position = _videoController!.value.position;
            _isPlaying = _videoController!.value.isPlaying;
          });
        }
      });

      setState(() {
        _isLoading = false;
        _isPlaying = true;
      });

      _videoController!.play();
    } catch (e, s) {
      Logs().e('Failed to load round video', e, s);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _togglePlay() {
    if (_videoController == null) {
      _loadAndPlay();
      return;
    }
    if (_isPlaying) {
      _videoController!.pause();
    } else {
      if (_position >= _duration) {
        _videoController!.seekTo(Duration.zero);
      }
      _videoController!.play();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final circleSize = 160.0;
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: SizedBox(
            width: circleSize,
            height: circleSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Circular video preview / thumbnail
                ClipOval(
                  child: _videoController != null && _videoController!.value.isInitialized
                      ? SizedBox(
                          width: circleSize,
                          height: circleSize,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: _videoController!.value.size.width,
                              height: _videoController!.value.size.height,
                              child: VideoPlayer(_videoController!),
                            ),
                          ),
                        )
                      : widget.event.hasThumbnail &&
                              AppSettings.showThumbnailsInTimeline.value
                          ? MxcImage(
                              event: widget.event,
                              cacheKey: widget.event.transactionId ?? widget.event.eventId,
                              cacheName: widget.event.room.id,
                              isThumbnail: true,
                              width: circleSize,
                              height: circleSize,
                              fit: BoxFit.cover,
                              placeholder: (context) => Container(
                                color: theme.colorScheme.surfaceContainerHigh,
                                child: const Icon(Icons.play_circle_outline, size: 48),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHigh,
                              child: const Icon(Icons.play_circle_outline, size: 48),
                            ),
                ),
                // Circular progress ring (non-interactive)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CircularProgressPainter(
                        progress: progress.clamp(0.0, 1.0),
                        color: theme.colorScheme.primary,
                        backgroundColor: Colors.white.withOpacity(0.2),
                      ),
                    ),
                  ),
                ),
                // Play/Pause button overlay
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ],
            ),
          ),
        ),
        // Duration text
        Text(
          _formatDuration(_position > Duration.zero ? _position : _duration),
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 3.0;

    // Background ring
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
