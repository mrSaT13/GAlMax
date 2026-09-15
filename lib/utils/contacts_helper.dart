// SPDX-FileCopyrightText: 2024 GAlMax Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as device_contacts;
import 'package:galmax/utils/localized_exception_extension.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Маркер связи в заметках контакта — по нему ищет звонок.
String _marker(String userId) => 'Matrix: $userId';

/// Сохранить пользователя Matrix в телефонную книгу: на выбор —
/// новый контакт или добавка к существующему из списка.
/// В Matrix ничего не отправляется — всё строго локально на телефоне.
Future<void> addMatrixUserToContacts(
  BuildContext context, {
  required String userId,
  required String displayName,
}) async {
  try {
    final choice = await showModalActionPopup<String>(
      context: context,
      title: displayName,
      message: userId,
      cancelLabel: 'Отмена',
      actions: [
        AdaptiveModalAction(
          value: 'new',
          label: 'Новый контакт',
        ),
        AdaptiveModalAction(
          value: 'existing',
          label: 'К существующему…',
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'new') {
      await _createContact(context, userId: userId, displayName: displayName);
    } else {
      await _attachToExisting(context, userId: userId, displayName: displayName);
    }
  } catch (e, s) {
    Logs().e('[Contacts] save failed $userId', e, s);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
  }
}

Future<void> _createContact(
  BuildContext context, {
  required String userId,
  required String displayName,
}) async {
  if (!await device_contacts.FlutterContacts.requestPermission(
    readonly: false,
  )) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступа к контактам')),
      );
    }
    return;
  }
  final name = displayName.isNotEmpty ? displayName : userId;
  final parts = name.split(' ');
  final contact = device_contacts.Contact()
    ..name.first = parts.first
    ..name.last = parts.length > 1 ? parts.sublist(1).join(' ') : ''
    ..notes = [device_contacts.Note('${_marker(userId)}\nGAlMax')];
  await contact.insert();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$name создан(а). Номер впиши в карточку в приложении Контакты.',
        ),
      ),
    );
  }
  Logs().i('[Contacts] created $userId as $name');
}

Future<void> _attachToExisting(
  BuildContext context, {
  required String userId,
  required String displayName,
}) async {
  if (!await device_contacts.FlutterContacts.requestPermission(
    readonly: false,
  )) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступа к контактам')),
      );
    }
    return;
  }
  final all = await device_contacts.FlutterContacts.getContacts(
    withProperties: true,
  );
  if (!context.mounted) return;
  if (all.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Книга пуста — создай новый контакт')),
    );
    return;
  }
  final picked = await showDialog<device_contacts.Contact>(
    context: context,
    builder: (dialogContext) => _ContactPickerDialog(
      contacts: all,
      title: 'К кому прикрепить $displayName?',
    ),
  );
  if (picked == null || !context.mounted) return;
  final full = await device_contacts.FlutterContacts.getContact(
    picked.id,
    withProperties: true,
    withAccounts: true,
  );
  final target = full ?? picked;
  if (target.notes.any((n) => n.note.contains(_marker(userId)))) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Уже прикреплён к этому контакту')),
    );
    return;
  }
  target.notes = [
    ...target.notes,
    device_contacts.Note('${_marker(userId)}\nGAlMax'),
  ];
  await target.update();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$displayName прикреплён к «${target.displayName}»'),
      ),
    );
  }
  Logs().i('[Contacts] attached $userId to ${target.displayName}');
}

/// Позвонить пользователю Matrix по номеру из телефонной книги.
/// Ищет контакт по маркеру `Matrix: <userId>` в заметках (его ставит
/// сохранение выше), запасной вариант — по отображаемому имени.
/// Открывает звонилку через tel: (ACTION_DIAL, без CALL_PHONE).
/// В Matrix номер не отправляется — всё строго локально на телефоне.
Future<void> callMatrixUserFromContacts(
  BuildContext context, {
  required String userId,
  required String displayName,
}) async {
  try {
    if (!await device_contacts.FlutterContacts.requestPermission(
      readonly: true,
    )) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к контактам')),
        );
      }
      return;
    }
    final contacts = await device_contacts.FlutterContacts.getContacts(
      withProperties: true,
    );
    // 1. Точное совпадение по маркеру из сохранения выше.
    var candidates = contacts
        .where((c) => c.notes.any((n) => n.note.contains(userId)))
        .toList();
    // 2. Запасной вариант — по имени.
    candidates = candidates.isNotEmpty
        ? candidates
        : contacts
            .where(
              (c) =>
                  c.displayName.isNotEmpty &&
                  (c.displayName.toLowerCase() ==
                          displayName.toLowerCase() ||
                      displayName.toLowerCase().contains(
                        c.displayName.toLowerCase(),
                      )),
            )
            .toList();
    final numbers = candidates
        .expand((c) => c.phones)
        .map((p) => p.number.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (!context.mounted) return;
    if (numbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Номера нет в книге. Сначала сохрани в контакты, потом впиши номер в карточку.',
          ),
        ),
      );
      return;
    }
    final number = numbers.length == 1
        ? numbers.single
        : await showModalActionPopup<String>(
            context: context,
            title: displayName,
            cancelLabel: 'Отмена',
            actions: [
              for (final n in numbers)
                AdaptiveModalAction(value: n, label: n),
            ],
          );
    if (number == null) return;
    await launchUrlString('tel:$number');
    Logs().i('[Contacts] dial $userId -> $number');
  } catch (e, s) {
    Logs().e('[Contacts] dial failed $userId', e, s);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
  }
}

/// Простой выбор контакта с поиском.
class _ContactPickerDialog extends StatefulWidget {
  final List<device_contacts.Contact> contacts;
  final String title;

  const _ContactPickerDialog({required this.contacts, required this.title});

  @override
  State<_ContactPickerDialog> createState() => _ContactPickerDialogState();
}

class _ContactPickerDialogState extends State<_ContactPickerDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final q = _filter.toLowerCase();
    final shown = q.isEmpty
        ? widget.contacts
        : widget.contacts
            .where(
              (c) =>
                  c.displayName.toLowerCase().contains(q) ||
                  c.phones.any((p) => p.number.contains(q)),
            )
            .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_outlined),
                hintText: 'Поиск',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              onChanged: (s) => setState(() => _filter = s),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Ничего не найдено'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final c = shown[i];
                        final phone = c.phones.firstOrNull?.number ?? '';
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              c.displayName.isEmpty
                                  ? '?'
                                  : c.displayName[0].toUpperCase(),
                            ),
                          ),
                          title: Text(
                            c.displayName.isEmpty ? '(без имени)' : c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: phone.isEmpty ? null : Text(phone),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}
