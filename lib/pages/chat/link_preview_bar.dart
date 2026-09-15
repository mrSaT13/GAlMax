// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Находит первую ссылку в тексте (без сетевых запросов — важно при
/// блокировках: превью не палит IP лишними запросами).
Uri? extractFirstLink(String text) {
  final match = RegExp(
    r'(https?:\/\/[^\s]+|www\.[^\s]+|[a-z0-9\-]+\.[a-z]{2,}(\/[^\s]*)?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  var raw = match.group(0)!;
  // Отрезаем trailing-пунктуацию из конца предложения.
  raw = raw.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
  if (raw.length < 4 || !raw.contains('.')) return null;
  final normalized = raw.startsWith(RegExp(r'https?://', caseSensitive: false))
      ? raw
      : 'https://$raw';
  return Uri.tryParse(normalized);
}

/// Компактная карточка ссылки над полем ввода, как в Telegram:
/// показывает, что именно уйдёт кликабельным. Тап — открыть.
class LinkPreviewBar extends StatelessWidget {
  final Uri url;
  final VoidCallback? onClose;

  const LinkPreviewBar({super.key, required this.url, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urlString = url.toString();
    final display = urlString.length > 64
        ? '${urlString.substring(0, 64)}…'
        : urlString;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(160),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Icon(
          Icons.link_outlined,
          color: theme.colorScheme.primary,
          size: 20,
        ),
        title: Text(
          url.host.isEmpty ? urlString : url.host,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: onClose == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
        onTap: () => launchUrlString(urlString),
      ),
    );
  }
}
