// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/utils/link_preview.dart';
import 'package:galmax/utils/url_launcher.dart';
import 'package:galmax/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Карточка превью ссылки под текстом сообщения, как в Telegram:
/// ссылка, название сайта, заголовок, описание, большая картинка.
class LinkPreviewCard extends StatelessWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;

  const LinkPreviewCard({
    required this.event,
    required this.textColor,
    required this.linkColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final url = extractFirstUrl(event.body);
    if (url == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return FutureBuilder<LinkPreviewData?>(
      future: fetchLinkPreview(event.room.client, url),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        if (preview == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => UrlLauncher(context, url).launchUrl(),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: accent, width: 2),
                ),
              ),
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: linkColor, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview.siteName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (preview.title != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      preview.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                  if (preview.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      preview.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withAlpha(200),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (preview.imageMxc != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: MxcImage(
                        uri: preview.imageMxc,
                        client: event.room.client,
                        fit: BoxFit.cover,
                        width: 320,
                        height: 170,
                        isThumbnail: true,
                        downloadWidth: 640,
                        downloadHeight: 340,
                        animated: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
