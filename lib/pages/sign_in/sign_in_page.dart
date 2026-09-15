// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:galmax/config/themes.dart';
import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:galmax/pages/sign_in/view_model/sign_in_view_model.dart';
import 'package:galmax/utils/localized_exception_extension.dart';
import 'package:galmax/utils/sign_in_flows/check_homeserver.dart';
import 'package:galmax/widgets/layouts/login_scaffold.dart';
import 'package:galmax/widgets/matrix.dart';
import 'package:galmax/widgets/view_model_builder.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SignInPage extends StatelessWidget {
  final bool signUp;
  const SignInPage({required this.signUp, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ViewModelBuilder(
      create: () => SignInViewModel(Matrix.of(context), signUp: signUp),
      builder: (context, viewModel, _) {
        final state = viewModel.value;
        final publicHomeservers = state.filteredPublicHomeservers;
        final selectedHomserver = state.selectedHomeserver;
        return LoginScaffold(
          appBar: AppBar(
            leading:
                state.loginLoading.connectionState == ConnectionState.waiting
                ? CloseButton(
                    onPressed: () =>
                        viewModel.setLoginLoading(AsyncSnapshot.nothing()),
                  )
                : BackButton(onPressed: Navigator.of(context).pop),
            backgroundColor: theme.colorScheme.surface,
            surfaceTintColor: theme.colorScheme.surface,
            scrolledUnderElevation: 0,
            centerTitle: true,
            title: Text(
              signUp
                  ? L10n.of(context).createNewAccount
                  : L10n.of(context).login,
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              spacing: 16,
              children: [
                SelectableText(
                  signUp
                      ? L10n.of(context).signUpGreeting
                      : L10n.of(context).signInGreeting,
                  textAlign: .center,
                ),
                TextField(
                  // Никаких автозапросов: поле пустое и сразу ждёт ввод URL.
                  readOnly:
                      state.loginLoading.connectionState ==
                      ConnectionState.waiting,
                  controller: viewModel.filterTextController,
                  autocorrect: false,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) {
                    final selected = state.selectedHomeserver;
                    if (selected != null &&
                        state.loginLoading.connectionState !=
                            ConnectionState.waiting) {
                      connectToHomeserverFlow(
                        selected,
                        context,
                        viewModel.setLoginLoading,
                        signUp,
                      );
                    }
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: theme.colorScheme.secondaryContainer,
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    errorText: state.publicHomeservers.error?.toLocalizedString(
                      context,
                    ),
                    prefixIcon: const Icon(Icons.dns_outlined),
                    suffixIcon:
                        viewModel.filterTextController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              viewModel.filterTextController.clear();
                              viewModel.selectHomeserver(null);
                            },
                          )
                        : null,
                    hintText: 'Введите адрес сервера, например matrix.org',
                  ),
                ),
                // Каталог общественных серверов — только по явному запросу.
                if (state.publicHomeservers.connectionState ==
                    ConnectionState.none)
                  OutlinedButton.icon(
                    onPressed: viewModel.loadPublicServers,
                    icon: const Icon(Icons.public_outlined),
                    label: const Text('Показать общественные серверы'),
                  ),
                if (state.publicHomeservers.connectionState ==
                    ConnectionState.waiting)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  ),
                if (state.publicHomeservers.hasError)
                  OutlinedButton.icon(
                    onPressed: viewModel.loadPublicServers,
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Повторить загрузку списка'),
                  ),
                if (state.publicHomeservers.connectionState ==
                    ConnectionState.done)
                  Expanded(
                    child: Material(
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius,
                      ),
                      clipBehavior: Clip.hardEdge,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: RadioGroup<PublicHomeserverData>(
                        groupValue: state.selectedHomeserver,
                        onChanged: viewModel.selectHomeserver,
                        child: ListView.builder(
                          itemCount: publicHomeservers.length,
                          itemBuilder: (context, i) {
                            final server = publicHomeservers[i];
                            final website = server.website;
                            return RadioListTile(
                              value: server,
                              enabled:
                                  state.loginLoading.connectionState !=
                                  ConnectionState.waiting,
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(server.name ?? 'Unknown'),
                                  ),
                                  if (website != null)
                                    SizedBox.square(
                                      dimension: 32,
                                      child: IconButton(
                                        tooltip: website,
                                        icon: const Icon(
                                          Icons.open_in_new_outlined,
                                          size: 16,
                                        ),
                                        onPressed: () =>
                                            launchUrlString(website),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                spacing: 4.0,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (server.features?.isNotEmpty == true)
                                    Wrap(
                                      spacing: 4.0,
                                      runSpacing: 4.0,
                                      children: [
                                        ...?server.languages?.map(
                                          (language) => Material(
                                            borderRadius: BorderRadius.circular(
                                              AppConfig.borderRadius,
                                            ),
                                            color: theme
                                                .colorScheme
                                                .tertiaryContainer,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6.0,
                                                    vertical: 3.0,
                                                  ),
                                              child: Text(
                                                language,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: theme
                                                      .colorScheme
                                                      .onTertiaryContainer,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        ...server.features!.map(
                                          (feature) => Material(
                                            borderRadius: BorderRadius.circular(
                                              AppConfig.borderRadius,
                                            ),
                                            color: theme
                                                .colorScheme
                                                .secondaryContainer,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6.0,
                                                    vertical: 3.0,
                                                  ),
                                              child: Text(
                                                feature,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: theme
                                                      .colorScheme
                                                      .onSecondaryContainer,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  Text(
                                    server.description ?? 'A matrix homeserver',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: AnimatedSize(
            duration: GalmaxThemes.animationDuration,
            curve: GalmaxThemes.animationCurve,
            child:
                selectedHomserver == null ||
                    !publicHomeservers.contains(selectedHomserver)
                ? const SizedBox.shrink()
                : Material(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SafeArea(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                          ),
                          onPressed:
                              state.loginLoading.connectionState ==
                                  ConnectionState.waiting
                              ? null
                              : () => connectToHomeserverFlow(
                                  selectedHomserver,
                                  context,
                                  viewModel.setLoginLoading,
                                  signUp,
                                ),
                          child:
                              state.loginLoading.connectionState ==
                                  ConnectionState.waiting
                              ? const CircularProgressIndicator.adaptive()
                              : Text(L10n.of(context).continueText),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
