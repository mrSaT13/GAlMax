// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';

import '../config/app_config.dart';
import '../utils/platform_infos.dart';
import '../utils/proximity_audio_helper.dart';
import 'matrix.dart';

/// Extension to check if audio is at end position
extension _AudioPlayerExt on AudioPlayer {
  bool get isAtEndPosition {
    final d = duration;
    if (d == null) return true;
    return position >= d;
  }
}

/// Persistent mini-player for audio/video messages (like Telegram)
/// Shows at the bottom of the chat list when media is playing
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final theme = Theme.of(context);

    return ValueListenableBuilder<String?>(
      valueListenable: matrix.voiceMessageEventId,
      builder: (context, eventId, _) {
        if (eventId == null || matrix.audioPlayer == null) {
          return const SizedBox.shrink();
        }

        final audioPlayer = matrix.audioPlayer!;
        return _MiniPlayerContent(
          audioPlayer: audioPlayer,
          eventId: eventId,
          matrix: matrix,
          theme: theme,
        );
      },
    );
  }
}

class _MiniPlayerContent extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final String eventId;
  final MatrixState matrix;
  final ThemeData theme;

  const _MiniPlayerContent({
    required this.audioPlayer,
    required this.eventId,
    required this.matrix,
    required this.theme,
  });

  @override
  State<_MiniPlayerContent> createState() => _MiniPlayerContentState();
}

class _MiniPlayerContentState extends State<_MiniPlayerContent> {
  String _senderName = '';
  String _roomName = '';

  @override
  void initState() {
    super.initState();
    _loadEventInfo();
  }

  @override
  void didUpdateWidget(_MiniPlayerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) {
      _loadEventInfo();
    }
  }

  void _loadEventInfo() {
    // Find the event in rooms to get sender and room info
    for (final room in widget.matrix.client.rooms) {
      try {
        final future = room.getEventById(widget.eventId);
        future.then((event) {
          if (event != null && mounted) {
            setState(() {
              _senderName = event.senderFromMemoryOrFallback.calcDisplayname();
              _roomName = room.getLocalizedDisplayname();
            });
          }
        });
      } catch (_) {}
    }
  }

  void _togglePlayPause() {
    if (widget.audioPlayer.isAtEndPosition) {
      widget.audioPlayer.seek(Duration.zero);
    } else if (widget.audioPlayer.playing) {
      widget.audioPlayer.pause();
    } else {
      widget.audioPlayer.play();
    }
  }

  void _close() {
    widget.audioPlayer.pause();
    widget.audioPlayer.dispose();
    widget.matrix.voiceMessageEventId.value = null;
    widget.matrix.audioPlayer = null;

    // Stop proximity sensor
    if (PlatformInfos.isMobile) {
      ProximityAudioHelper.instance.onPlaybackStopped();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: widget.theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: StreamBuilder(
        stream: widget.audioPlayer.playerStateStream,
        builder: (context, _) {
          final isPlaying = widget.audioPlayer.playing && !widget.audioPlayer.isAtEndPosition;
          return StreamBuilder(
            stream: widget.audioPlayer.positionStream,
            builder: (context, _) {
              final position = widget.audioPlayer.position;
              final duration = widget.audioPlayer.duration ?? Duration.zero;
              final progress = duration.inMilliseconds > 0
                  ? position.inMilliseconds / duration.inMilliseconds
                  : 0.0;

              return Row(
                children: [
                  // Play/Pause button
                  IconButton(
                    onPressed: _togglePlayPause,
                    icon: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: widget.theme.colorScheme.primary,
                      size: 32,
                    ),
                  ),
                  // Progress bar and info
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _senderName.isNotEmpty ? _senderName : _roomName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: widget.theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              _formatDuration(position),
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                backgroundColor: widget.theme.colorScheme.onSurface.withOpacity(0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.theme.colorScheme.primary,
                                ),
                                minHeight: 2,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(duration),
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  IconButton(
                    onPressed: _close,
                    icon: Icon(
                      Icons.close_rounded,
                      color: widget.theme.colorScheme.onSurface.withOpacity(0.6),
                      size: 20,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
