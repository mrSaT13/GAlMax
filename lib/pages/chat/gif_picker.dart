// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:galmax/utils/gif_provider.dart';
import 'package:flutter/material.dart';

class GifPicker extends StatefulWidget {
  final void Function(String gifUrl) onGifSelected;

  const GifPicker({required this.onGifSelected, super.key});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  final _gifProvider = GifProvider();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<GifItem> _gifs = [];
  List<GifItem> _recent = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String _lastQuery = '';
  int _offset = 0;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _loadRecent();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final recent = await GifRecentStorage.load();
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  Future<void> _onGifTap(GifItem gif) async {
    final updated = await GifRecentStorage.save(gif);
    if (mounted) setState(() => _recent = updated);
    widget.onGifSelected(gif.url);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadTrending() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final gifs = await _gifProvider.trending(limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _gifs = gifs;
      _isLoading = false;
      _offset = gifs.length;
      _hasMore = gifs.length >= _pageSize;
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _loadTrending();
      return;
    }
    setState(() {
      _isLoading = true;
      _lastQuery = query;
      _offset = 0;
      _hasMore = true;
    });
    final gifs = await _gifProvider.search(query, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _gifs = gifs;
      _isLoading = false;
      _offset = gifs.length;
      _hasMore = gifs.length >= _pageSize;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    List<GifItem> moreGifs;
    if (_lastQuery.isNotEmpty) {
      moreGifs = await _gifProvider.search(
        _lastQuery,
        limit: _pageSize,
        offset: _offset,
      );
    } else {
      moreGifs = await _gifProvider.trending(
        limit: _pageSize,
        offset: _offset,
      );
    }
    if (!mounted) return;
    setState(() {
      _gifs.addAll(moreGifs);
      _offset += moreGifs.length;
      _isLoading = false;
      _hasMore = moreGifs.length >= _pageSize;
    });
  }

  void _toggleProvider() {
    setState(() {
      _gifProvider.setProvider(
        _gifProvider.activeProvider == GifProviderType.giphy
            ? GifProviderType.tenor
            : GifProviderType.giphy,
      );
      _offset = 0;
      _hasMore = true;
      _lastQuery = '';
    });
    if (_searchController.text.isEmpty) {
      _loadTrending();
    } else {
      _search(_searchController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 320,
      color: isDark ? AppConfig.darkCard : theme.colorScheme.surface,
      child: Column(
        children: [
          // Provider toggle + Search bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Provider toggle
                GestureDetector(
                  onTap: _toggleProvider,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.gif_box_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _gifProvider.activeProvider == GifProviderType.giphy
                              ? 'GIPHY'
                              : 'Tenor',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.swap_horiz,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Search field
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppConfig.darkBackground
                          : theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: _search,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search GIFs...',
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onSurface.withAlpha(100),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: theme.colorScheme.onSurface.withAlpha(150),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Recent GIFs
          if (_recent.isNotEmpty && _lastQuery.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Text(
                    'Recent',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await GifRecentStorage.clear();
                      if (mounted) setState(() => _recent = []);
                    },
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final gif = _recent[index];
                  return GestureDetector(
                    onTap: () => _onGifTap(gif),
                    child: Container(
                      width: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: isDark ? AppConfig.darkBackground : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        gif.previewUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // GIF grid
          Expanded(
            child: _gifs.isEmpty && _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : _gifs.isEmpty
                    ? Center(
                        child: Text(
                          'No GIFs found',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withAlpha(150),
                          ),
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(4),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          childAspectRatio: 1,
                        ),
                        itemCount: _gifs.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _gifs.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            );
                          }
                          final gif = _gifs[index];
                          return _buildGifItem(gif, isDark);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGifItem(GifItem gif, bool isDark) {
    return GestureDetector(
      onTap: () => _onGifTap(gif),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isDark ? AppConfig.darkBackground : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          gif.previewUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: Theme.of(context).colorScheme.primary,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            final errorTheme = Theme.of(context);
            return Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: errorTheme.colorScheme.onSurface.withAlpha(100),
              ),
            );
          },
        ),
      ),
    );
  }
}
