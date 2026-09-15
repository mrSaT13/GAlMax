// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GifItem {
  final String id;
  final String url;
  final String previewUrl;
  final String title;
  final int width;
  final int height;

  const GifItem({
    required this.id,
    required this.url,
    required this.previewUrl,
    required this.title,
    this.width = 200,
    this.height = 200,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'previewUrl': previewUrl,
        'title': title,
        'width': width,
        'height': height,
      };

  factory GifItem.fromJson(Map<String, Object?> json) => GifItem(
        id: json['id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        previewUrl: json['previewUrl'] as String? ?? '',
        title: json['title'] as String? ?? '',
        width: (json['width'] as num?)?.toInt() ?? 200,
        height: (json['height'] as num?)?.toInt() ?? 200,
      );
}

/// Last-used GIFs, stored locally. Shown on top of the picker.
abstract class GifRecentStorage {
  static const String _key = 'im.galmax.recent_gifs';
  static const int maxCount = 30;

  static Future<List<GifItem>> load() async {
    try {
      final store = await SharedPreferences.getInstance();
      final raw = store.getStringList(_key) ?? const [];
      return raw
          .map((e) {
            try {
              return GifItem.fromJson(
                jsonDecode(e) as Map<String, Object?>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<GifItem>()
          .where((g) => g.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<GifItem>> save(GifItem gif) async {
    final current = await load();
    current.removeWhere((g) => g.id == gif.id || g.url == gif.url);
    current.insert(0, gif);
    final trimmed = current.take(maxCount).toList();
    try {
      final store = await SharedPreferences.getInstance();
      await store.setStringList(
        _key,
        trimmed.map((g) => jsonEncode(g.toJson())).toList(),
      );
    } catch (_) {}
    return trimmed;
  }

  static Future<void> clear() async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.remove(_key);
    } catch (_) {}
  }
}

enum GifProviderType { giphy, tenor }

class GifProvider {
  // Giphy API — ключ задается через --dart-define=GIPHY_API_KEY=... / GIPHY_SDK_KEY=...
  // В репо не коммитим секреты (GitHub Secret Scanning).
  static const String _giphyApiKey = String.fromEnvironment(
    'GIPHY_API_KEY',
    defaultValue: '',
  );
  static const String giphySdkKey = String.fromEnvironment(
    'GIPHY_SDK_KEY',
    defaultValue: '',
  );
  static const String _giphyBaseUrl = 'https://api.giphy.com/v1/gifs';

  // Tenor API
  static const String _tenorApiKey = ''; // TODO: Add Tenor API key
  static const String _tenorBaseUrl = 'https://tenor.googleapis.com/v2';

  GifProviderType _activeProvider = GifProviderType.giphy;
  GifProviderType get activeProvider => _activeProvider;

  void setProvider(GifProviderType provider) {
    _activeProvider = provider;
  }

  Future<List<GifItem>> search(String query, {int limit = 20, int offset = 0}) async {
    switch (_activeProvider) {
      case GifProviderType.giphy:
        return _searchGiphy(query, limit: limit, offset: offset);
      case GifProviderType.tenor:
        return _searchTenor(query, limit: limit, offset: offset);
    }
  }

  Future<List<GifItem>> trending({int limit = 20, int offset = 0}) async {
    switch (_activeProvider) {
      case GifProviderType.giphy:
        return _trendingGiphy(limit: limit, offset: offset);
      case GifProviderType.tenor:
        return _trendingTenor(limit: limit, offset: offset);
    }
  }

  // Giphy

  Future<List<GifItem>> _searchGiphy(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final uri = Uri.parse(
        '$_giphyBaseUrl/search?api_key=$_giphyApiKey&q=${Uri.encodeComponent(query)}&limit=$limit&offset=$offset&rating=g&lang=en',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data'] as List? ?? [];
      return results.map((gif) {
        final images = gif['images'] as Map?;
        final original = images?['original'] as Map?;
        final preview = images?['fixed_height'] as Map?;
        return GifItem(
          id: gif['id'] ?? '',
          url: original?['url'] ?? '',
          previewUrl: preview?['url'] ?? original?['url'] ?? '',
          title: gif['title'] ?? '',
          width: int.tryParse('${original?['width'] ?? 200}') ?? 200,
          height: int.tryParse('${original?['height'] ?? 200}') ?? 200,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<GifItem>> _trendingGiphy({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final uri = Uri.parse(
        '$_giphyBaseUrl/trending?api_key=$_giphyApiKey&limit=$limit&offset=$offset&rating=g',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data'] as List? ?? [];
      return results.map((gif) {
        final images = gif['images'] as Map?;
        final original = images?['original'] as Map?;
        final preview = images?['fixed_height'] as Map?;
        return GifItem(
          id: gif['id'] ?? '',
          url: original?['url'] ?? '',
          previewUrl: preview?['url'] ?? original?['url'] ?? '',
          title: gif['title'] ?? '',
          width: int.tryParse('${original?['width'] ?? 200}') ?? 200,
          height: int.tryParse('${original?['height'] ?? 200}') ?? 200,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Tenor

  Future<List<GifItem>> _searchTenor(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    if (_tenorApiKey.isEmpty) return [];
    try {
      final uri = Uri.parse(
        '$_tenorBaseUrl/search?key=$_tenorApiKey&q=${Uri.encodeComponent(query)}&limit=$limit&pos=$offset&media_filter=tinygif,gif',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['results'] as List? ?? [];
      return results.map((gif) {
        final mediaFormats = gif['media_formats'] as Map?;
        final gifFormat = mediaFormats?['gif'] as Map?;
        final tinyGif = mediaFormats?['tinygif'] as Map?;
        return GifItem(
          id: gif['id'] ?? '',
          url: gifFormat?['url'] ?? '',
          previewUrl: tinyGif?['url'] ?? gifFormat?['url'] ?? '',
          title: gif['title'] ?? '',
          width: int.tryParse('${gifFormat?['dims']?[0] ?? 200}') ?? 200,
          height: int.tryParse('${gifFormat?['dims']?[1] ?? 200}') ?? 200,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<GifItem>> _trendingTenor({
    int limit = 20,
    int offset = 0,
  }) async {
    if (_tenorApiKey.isEmpty) return [];
    try {
      final uri = Uri.parse(
        '$_tenorBaseUrl/featured?key=$_tenorApiKey&limit=$limit&pos=$offset&media_filter=tinygif,gif',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['results'] as List? ?? [];
      return results.map((gif) {
        final mediaFormats = gif['media_formats'] as Map?;
        final gifFormat = mediaFormats?['gif'] as Map?;
        final tinyGif = mediaFormats?['tinygif'] as Map?;
        return GifItem(
          id: gif['id'] ?? '',
          url: gifFormat?['url'] ?? '',
          previewUrl: tinyGif?['url'] ?? gifFormat?['url'] ?? '',
          title: gif['title'] ?? '',
          width: int.tryParse('${gifFormat?['dims']?[0] ?? 200}') ?? 200,
          height: int.tryParse('${gifFormat?['dims']?[1] ?? 200}') ?? 200,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }
}
