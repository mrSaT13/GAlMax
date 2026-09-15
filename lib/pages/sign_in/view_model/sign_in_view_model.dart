// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:galmax/config/app_config.dart';
import 'package:galmax/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:galmax/pages/sign_in/view_model/sign_in_state.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

class SignInViewModel extends ValueNotifier<SignInState> {
  final MatrixState matrixService;
  final bool signUp;
  final TextEditingController filterTextController = TextEditingController();

  SignInViewModel(this.matrixService, {required this.signUp})
    : super(SignInState()) {
    // Никуда не ломимся при открытии: просто ждём ввод URL.
    // Список общественных серверов грузится только по кнопке.
    value.publicHomeservers = const AsyncSnapshot.nothing();
    value.filteredPublicHomeservers = [];
    value.selectedHomeserver = null;
    filterTextController.addListener(_filterHomeservers);
  }

  @override
  void dispose() {
    filterTextController.removeListener(_filterHomeservers);
    super.dispose();
  }

  void _filterHomeservers() {
    final filterText = filterTextController.text.trim().toLowerCase();
    final filteredPublicHomeservers =
        value.publicHomeservers.data
            ?.where(
              (homeserver) =>
                  homeserver.name?.toLowerCase().contains(filterText) ?? false,
            )
            .toList() ??
        [];
    if (filterText.length >= 3 &&
        (filterText.contains('.') || filterText.endsWith('localhost')) &&
        Uri.tryParse(filterText) != null &&
        !filteredPublicHomeservers.any(
          (homeserver) => homeserver.name == filterText,
        )) {
      final custom = PublicHomeserverData(name: filterText);
      filteredPublicHomeservers.insert(0, custom);
      // Сразу подставляем введённый URL в выбор — кнопка
      // «Продолжить» доступна без ожидания списка серверов.
      value.selectedHomeserver = custom;
    } else if (filterText.isEmpty) {
      value.selectedHomeserver ??= value.publicHomeservers.data?.firstOrNull;
    }
    value.filteredPublicHomeservers = filteredPublicHomeservers;
    notifyListeners();
  }

  /// Ручная загрузка каталога общественных серверов (по кнопке).
  /// Без вызова — никаких сетевых запросов.
  Future<void> loadPublicServers() async {
    value.publicHomeservers = const AsyncSnapshot.waiting();
    notifyListeners();
    try {
      final client = await matrixService.getLoginClient();
      final response = await client.httpClient.get(AppConfig.homeserverList);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final homeserverJsonList = json['public_servers'] as List;

      final publicHomeservers = homeserverJsonList
          .map((json) => PublicHomeserverData.fromJson(json))
          .toList();

      if (signUp) {
        publicHomeservers.removeWhere((server) {
          return server.regMethod == null;
        });
      }

      value.publicHomeservers = AsyncSnapshot.withData(
        ConnectionState.done,
        publicHomeservers,
      );
      notifyListeners();
    } catch (e, s) {
      Logs().w('Unable to fetch public homeservers...', e, s);
      value.publicHomeservers = AsyncSnapshot.withError(
        ConnectionState.done,
        e,
      );
      notifyListeners();
    }
    _filterHomeservers();
  }

  /// Обратная совместимость: раньше список грузился сам.
  Future<void> refreshPublicHomeservers() => loadPublicServers();

  void selectHomeserver(PublicHomeserverData? publicHomeserverData) {
    value.selectedHomeserver = publicHomeserverData;
    notifyListeners();
  }

  void setLoginLoading(AsyncSnapshot<bool> loginLoading) {
    value.loginLoading = loginLoading;
    notifyListeners();
  }
}
