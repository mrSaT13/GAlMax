// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/setting_keys.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:galmax/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:galmax/widgets/app_lock.dart';
import 'package:galmax/widgets/future_loading_dialog.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'settings_security_view.dart';

class SettingsSecurity extends StatefulWidget {
  const SettingsSecurity({super.key});

  @override
  SettingsSecurityController createState() => SettingsSecurityController();
}

class SettingsSecurityController extends State<SettingsSecurity> {
  Future<void> setAppLockAction() async {
    final l10n = L10n.of(context);
    final appLock = AppLock.of(context);
    if (appLock.isActive) {
      // PIN уже стоит: предложить сменить или выключить.
      final action = await showModalActionPopup<_AppLockAction>(
        context: context,
        title: l10n.appLock,
        cancelLabel: l10n.cancel,
        actions: [
          AdaptiveModalAction(
            label: l10n.changePassword,
            value: _AppLockAction.change,
          ),
          AdaptiveModalAction(
            label: l10n.delete,
            value: _AppLockAction.disable,
            isDestructive: true,
          ),
        ],
      );
      if (action == null || !mounted) return;
      if (action == _AppLockAction.disable) {
        await showFutureLoadingDialog(
          context: context,
          future: () => appLock.changePincode(null),
        );
        return;
      }
      // change — идём дальше к диалогу ввода нового PIN.
    }
    final newLock = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.pleaseChooseAPasscode,
      message: l10n.pleaseEnter4Digits,
      cancelLabel: l10n.cancel,
      validator: (text) {
        // Без '!' — крашилось на нецифровом вводе (int.tryParse -> null!).
        if (text.length == 4 && int.tryParse(text) != null) return null;
        return l10n.pleaseEnter4Digits;
      },
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLines: 1,
      minLines: 1,
      maxLength: 4,
    );
    if (newLock != null) {
      if (!mounted) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => AppLock.of(context).changePincode(newLock),
      );
    }
  }

  Future<void> deleteAccountAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: l10n.warning,
          message: l10n.deactivateAccountWarning,
          okLabel: l10n.ok,
          cancelLabel: l10n.cancel,
          isDestructive: true,
        ) ==
        OkCancelResult.cancel) {
      return;
    }
    if (!mounted) return;
    final supposedMxid = matrix.client.userID!;
    final mxid = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.confirmMatrixId,
      validator: (text) =>
          text == supposedMxid ? null : l10n.supposedMxid(supposedMxid),
      isDestructive: true,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
    );
    if (mxid == null || mxid.isEmpty || mxid != supposedMxid) {
      return;
    }
    if (!mounted) return;
    final resp = await showFutureLoadingDialog(
      context: context,
      delay: false,
      future: () => matrix.client.uiaRequestBackground<IdServerUnbindResult?>(
        (auth) => matrix.client.deactivateAccount(auth: auth, erase: true),
      ),
    );

    if (!resp.isError) {
      if (!mounted) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.logout(),
      );
    }
  }

  Future<void> dehydrateAction() => Matrix.of(context).dehydrateAction(context);

  Future<void> changeShareKeysWith(ShareKeysWith? shareKeysWith) async {
    if (shareKeysWith == null) return;
    AppSettings.shareKeysWith.setItem(shareKeysWith.name);
    Matrix.of(context).client.shareKeysWith = shareKeysWith;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsSecurityView(this);
}

enum _AppLockAction { change, disable }
