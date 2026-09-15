// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/file_selector.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:galmax/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import '../../widgets/matrix.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;

  void updateProfile() => setState(() {
    profileUpdated = true;
    profileFuture = null;
  });

  Future<void> setDisplaynameAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final profile = await profileFuture;
    if (!mounted) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.editDisplayname,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: profile?.displayName ?? matrix.client.userID!.localpart,
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  Future<void> logoutAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final consent = await showOkCancelAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.areYouSureYouWantToLogout,
      message: l10n.noBackupWarning,
      isDestructive: cryptoIdentityConnected == false,
      okLabel: l10n.logout,
      cancelLabel: l10n.cancel,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.logout(),
    );
    if (!mounted) return;
    context.go('/');
  }

  Future<void> setAvatarAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final profile = await profileFuture;
    if (!mounted) return;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: l10n.openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: l10n.openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (profile?.avatarUrl != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: l10n.removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: l10n.changeYourAvatar,
            cancelLabel: l10n.cancel,
            actions: actions,
          );
    if (action == null) return;
    if (!mounted) return;
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setAvatar(null),
      );
      if (success.error == null) {
        updateProfile();
      }
      return;
    }
    MatrixFile file;
    try {
      if (PlatformInfos.isMobile) {
        // Без imageQuality: компрессия пикерубивала бы анимацию GIF.
        final result = await ImagePicker().pickImage(
          source: action == AvatarAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
        );
        if (result == null) return;
        file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
      } else {
        if (!mounted) return;
        final result = await selectFiles(context, type: FileType.image);
        final pickedFile = result.firstOrNull;
        if (pickedFile == null) return;
        file = MatrixFile(
          bytes: await pickedFile.readAsBytes(),
          name: pickedFile.name,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.oopsSomethingWentWrong)),
      );
      return;
    }
    if (!mounted) return;
    // Анимированные не кропаем: кроппер их либо роняет
    // нативно, либо убивает анимацию. Грузим как есть.
    // Детект по байтам, а не только по расширению: image_picker
    // может вернуть путь без расширения, а с камеры GIF не бывает.
    final cropped = _isAnimatedImage(file.bytes, file.name)
        ? file
        : await _cropAvatarToCircle(file);
    if (cropped == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(cropped),
    );
    if (success.error == null) {
      updateProfile();
      // Шапка берёт avatar_url из room-стейта, а не из профиля:
      // дёргаем синк, иначе висит старая аватарка до следующего синка.
      try {
        await matrix.client.oneShotSync();
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  /// Круглый кроп аватарки (UCrop / TOCropViewController).
  /// Null — пользователь отменил, тогда ничего не загружаем.
  /// Ошибка кроппера — отдаём оригинал, чтобы не терять выбор.
  ///
  /// Детект анимации по магическим байтам: GIF87a/GIF89a, WebP VP8X с
  /// флагом ANIM, APNG с чанком acTL. Расширению не доверяем.
  static bool _isAnimatedImage(List<int> bytes, String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.gif') || lower.endsWith('.webp')) return true;
    if (bytes.length < 12) return false;
    // GIF
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return true;
    }
    // WebP: RIFF....WEBPVP8X + бит анимации (байт 12 & 0x02).
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      if (bytes.length > 13 && (bytes[12] & 0x02) != 0) return true;
      // VP8X без флага тоже может быть анимированным — проверяем acTL нет,
      // для WebP доверяемся расширению выше + эвристике: ищем 'ANIM' чанк.
      for (var i = 12; i + 4 < bytes.length && i < 64; i++) {
        if (bytes[i] == 0x41 &&
            bytes[i + 1] == 0x4E &&
            bytes[i + 2] == 0x49 &&
            bytes[i + 3] == 0x4D) {
          return true;
        }
      }
    }
    // PNG: ищем чанк acTL (APNG).
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      for (var i = 8; i + 8 < bytes.length && i < 256; i++) {
        if (bytes[i] == 0x61 &&
            bytes[i + 1] == 0x63 &&
            bytes[i + 2] == 0x54 &&
            bytes[i + 3] == 0x4C) {
          return true;
        }
      }
    }
    return false;
  }
  Future<MatrixFile?> _cropAvatarToCircle(MatrixFile file) async {
    try {
      final tmp = await getTemporaryDirectory();
      final src = File(
        '${tmp.path}/avatar_src_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await src.writeAsBytes(file.bytes);
      final cropped = await ImageCropper().cropImage(
        sourcePath: src.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 512,
        maxHeight: 512,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Аватарка',
            cropStyle: CropStyle.circle,
            lockAspectRatio: true,
            hideBottomControls: true,
          ),
          IOSUiSettings(
            title: 'Аватарка',
            cropStyle: CropStyle.circle,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );
      try {
        await src.delete();
      } catch (_) {}
      if (cropped == null) return null;
      return MatrixFile(
        bytes: await cropped.readAsBytes(),
        name: 'avatar.jpg',
      );
    } catch (_) {
      return file;
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());

    super.initState();
  }

  Future<void> checkBootstrap() async {
    final client = Matrix.of(context).client;
    if (!client.encryptionEnabled) return;
    if (!client.isLogged()) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }

    final state = await client.getCryptoIdentityState();
    if (!mounted) return;
    setState(() {
      cryptoIdentityConnected = state.initialized && state.connected;
    });
  }

  bool? cryptoIdentityConnected;

  Future<void> firstRunBootstrapAction([_]) async {
    if (cryptoIdentityConnected == true) {
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).close,
      );
      return;
    }
    await context.push('/backup');
    checkBootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    profileFuture ??= client.getProfileFromUserId(client.userID!);
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }
