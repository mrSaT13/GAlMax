// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:galmax/utils/timeline_mutex.dart';
import 'package:galmax/widgets/future_loading_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:share_plus/share_plus.dart';

/// Экспорт истории чата в HTML/TXT через системный Share-sheet.
/// Берёт до 1000 последних видимых событий из свежего таймлайна.
/// Чтение идёт через общий мьютекс с открытием чата, иначе параллельные
/// getTimeline роняют sqflite (SqliteException 21).
Future<void> exportChat(BuildContext context, Room room) async {
  final format = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Экспорт чата'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop('html'),
          child: const Row(
            children: [
              Icon(Icons.html_outlined),
              SizedBox(width: 12),
              Text('HTML-файл'),
            ],
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop('txt'),
          child: const Row(
            children: [
              Icon(Icons.description_outlined),
              SizedBox(width: 12),
              Text('Текстовый файл'),
            ],
          ),
        ),
      ],
    ),
  );
  if (format == null || !context.mounted) return;

  final result = await showFutureLoadingDialog(
    context: context,
    future: () => _buildExport(room, format),
  );
  if (result.error != null || !context.mounted) return;
  final data = result.result!;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          data.$1,
          name: data.$2,
          mimeType: format == 'html' ? 'text/html' : 'text/plain',
        ),
      ],
      text: 'Экспорт чата ${room.getLocalizedDisplayname()}',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

Future<(Uint8List, String)> _buildExport(Room room, String format) async {
  return TimelineMutex.run(() => _buildExportInner(room, format));
}

Future<(Uint8List, String)> _buildExportInner(
  Room room,
  String format,
) async {
  final timeline = await room.getTimeline();
  try {
    final events = timeline.events
        .where((e) => e.type == EventTypes.Message || e.type == EventTypes.Sticker)
        .take(1000)
        .toList()
        .reversed
        .toList();
    final name = room
        .getLocalizedDisplayname()
        .replaceAll(RegExp(r'[^\wа-яА-ЯёЁ\- ]', caseSensitive: false), '_')
        .trim();
    if (format == 'html') {
      final buf = StringBuffer()
        ..writeln('<!DOCTYPE html><html><head><meta charset="utf-8">')
        ..writeln('<title>${_esc(name)}</title></head><body>')
        ..writeln('<h1>${_esc(name)}</h1>');
      for (final e in events) {
        final sender = _esc(e.senderFromMemoryOrFallback.calcDisplayname());
        final time = e.originServerTs.toIso8601String();
        final body = _esc(e.plaintextBody);
        buf.writeln(
          '<p><b>$sender</b> <small>$time</small><br>$body</p>',
        );
      }
      buf.writeln('</body></html>');
      return (Uint8List.fromList(utf8.encode(buf.toString())), 'chat-$name.html');
    }
    final buf = StringBuffer('Чат: $name\n\n');
    for (final e in events) {
      buf.writeln(
        '[${e.originServerTs.toIso8601String()}] '
        '${e.senderFromMemoryOrFallback.calcDisplayname()}: '
        '${e.plaintextBody}',
      );
    }
    return (
      Uint8List.fromList(utf8.encode(buf.toString())),
      'chat-$name.txt',
    );
  } finally {
    timeline.cancelSubscriptions();
  }
}

String _esc(String s) => const HtmlEscape().convert(s);
