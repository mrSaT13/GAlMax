// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:galmax/config/themes.dart';
import 'package:galmax/utils/client_download_content_extension.dart';
import 'package:galmax/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class MxcImage extends StatefulWidget {
  final Uri? uri;
  final Event? event;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isThumbnail;
  final bool animated;
  final Duration retryDuration;
  final Duration animationDuration;
  final Curve animationCurve;
  final ThumbnailMethod thumbnailMethod;
  final Widget Function(BuildContext context)? placeholder;
  final String? cacheKey;
  final String? cacheName;
  final Client? client;
  final BorderRadius borderRadius;
  final double? downloadWidth;
  final double? downloadHeight;

  static void clearCache(String cacheName) =>
      _MxcImageState._imageDataCaches.remove(cacheName);

  const MxcImage({
    this.uri,
    this.event,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.isThumbnail = true,
    this.animated = false,
    this.animationDuration = GalmaxThemes.animationDuration,
    this.retryDuration = const Duration(seconds: 2),
    this.animationCurve = GalmaxThemes.animationCurve,
    this.thumbnailMethod = ThumbnailMethod.scale,
    this.cacheKey,
    this.client,
    this.borderRadius = BorderRadius.zero,
    this.cacheName,
    this.downloadWidth,
    this.downloadHeight,
    super.key,
  });

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  static final Map<String?, Map<String, Uint8List>> _imageDataCaches = {};
  Map<String, Uint8List> get _imageDataCache =>
      _imageDataCaches[widget.cacheName ?? ''] ??= {};

  Uint8List? _imageDataNoCache;

  Uint8List? get _imageData => widget.cacheKey == null
      ? _imageDataNoCache
      : _imageDataCache[widget.cacheKey];

  set _imageData(Uint8List? data) {
    if (data == null || data.isEmpty) return;
    final cacheKey = widget.cacheKey;
    if (cacheKey == null) {
      _imageDataNoCache = data;
      return;
    }
    // Bound memory usage: drop oldest entries past the cap.
    if (!_imageDataCache.containsKey(cacheKey) &&
        _imageDataCache.length >= 300) {
      _imageDataCache.remove(_imageDataCache.keys.first);
    }
    _imageDataCache[cacheKey] = data;
  }

  Future<void> _load() async {
    if (!mounted) return;
    final client =
        widget.client ?? widget.event?.room.client ?? Matrix.of(context).client;
    final uri = widget.uri;
    final event = widget.event;

    if (uri != null) {
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final width = widget.downloadWidth ?? widget.width;
      final realWidth = width == null ? null : width * devicePixelRatio;
      final height = widget.downloadHeight ?? widget.height;
      final realHeight = height == null ? null : height * devicePixelRatio;

      final remoteData = await client.downloadMxcCached(
        uri,
        width: realWidth,
        height: realHeight,
        thumbnailMethod: widget.thumbnailMethod,
        isThumbnail: widget.isThumbnail,
        animated: widget.animated,
      );
      if (!mounted) return;
      setState(() {
        _imageData = remoteData;
      });
    }

    if (event != null) {
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: widget.isThumbnail,
      );
      if (data.detectFileType is MatrixImageFile || widget.isThumbnail) {
        if (!mounted) return;
        setState(() {
          _imageData = data.bytes;
        });
        return;
      }
    }
  }

  Future<void> _tryLoad() async {
    if (_imageData != null && _imageData!.isNotEmpty) {
      return;
    }
    try {
      await _load();
    } catch (_) {
      if (!mounted) return;
      await Future.delayed(widget.retryDuration);
      _tryLoad();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;

    return AnimatedCrossFade(
      duration: GalmaxThemes.animationDuration,
      firstChild: ClipRRect(
        borderRadius: widget.borderRadius,
        child: data == null
            ? _MxcImagePlaceholder(
                width: widget.width,
                height: widget.height,
                placeholder: widget.placeholder,
              )
            : Image.memory(
                data,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                // GIF не перезапускается при перестроениях списка.
                gaplessPlayback: true,
                filterQuality: widget.isThumbnail
                    ? FilterQuality.low
                    : FilterQuality.medium,
                errorBuilder: (context, e, s) {
                  Logs().d('Unable to render mxc image', e, s);
                  return SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: min(widget.height ?? 64, 64),
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  );
                },
              ),
      ),
      secondChild: _MxcImagePlaceholder(
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
      ),
      crossFadeState: hasData
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
    );
  }
}

class _MxcImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? placeholder;

  const _MxcImagePlaceholder({
    required this.width,
    required this.height,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return placeholder?.call(context) ??
        Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
  }
}
