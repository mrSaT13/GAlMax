// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart';

/// Превью ссылок как в Telegram: заголовок + описание + картинка.
/// Данные берёт серверный `GET /_matrix/media/v3/preview_url` (сервер сам
/// ходит за страницей, клиентский IP не светится, CORS не мешает).
/// Кэш только в памяти на сессию: превью протухают, хранить в базе смысла нет.
class LinkPreviewData {
  final String url;
  final String siteName;
  final String? title;
  final String? description;
  final Uri? imageMxc;

  const LinkPreviewData({
    required this.url,
    required this.siteName,
    this.title,
    this.description,
    this.imageMxc,
  });

  bool get isEmpty => title == null && description == null && imageMxc == null;
}

final _urlRegex = RegExp(r'https?://[^\s<>"`]+');

/// Первая http(s)-ссылка в тексте или null.
String? extractFirstUrl(String text) {
  final match = _urlRegex.firstMatch(text);
  if (match == null) return null;
  var url = match.group(0)!;
  // Чистим хвост пунктуации, прилипшей из предложения.
  while (url.isNotEmpty && '.,!?)]};:\'"'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority) return null;
  return url;
}

final Map<String, LinkPreviewData?> _previewCache = {};

Future<LinkPreviewData?> fetchLinkPreview(
  Client client,
  String url, {
  bool refresh = false,
}) async {
  if (!refresh && _previewCache.containsKey(url)) {
    return _previewCache[url];
  }
  try {
    final homeserver = client.homeserver;
    if (homeserver == null) return null;
    final endpoint = Uri(
      scheme: homeserver.scheme,
      host: homeserver.host,
      port: homeserver.hasPort ? homeserver.port : null,
      path: '/_matrix/media/v3/preview_url',
      queryParameters: {'url': url},
    );
    final token = client.accessToken;
    final response = await client.httpClient
        .get(
          endpoint,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      _previewCache[url] = null;
      return null;
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) {
      _previewCache[url] = null;
      return null;
    }
    final site = (json['og:site_name'] as String?)?.trim();
    final data = LinkPreviewData(
      url: url,
      siteName: (site != null && site.isNotEmpty)
          ? site
          : (Uri.tryParse(url)?.host ?? url),
      title: (json['og:title'] as String?)?.trim(),
      description: (json['og:description'] as String?)?.trim(),
      imageMxc: json['og:image'] is String
          ? Uri.tryParse(json['og:image'] as String)
          : null,
    );
    _previewCache[url] = data.isEmpty ? null : data;
    return _previewCache[url];
  } catch (_) {
    _previewCache[url] = null;
    return null;
  }
}
