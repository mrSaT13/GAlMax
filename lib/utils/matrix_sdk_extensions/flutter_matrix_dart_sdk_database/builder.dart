// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:galmax/l10n/l10n.dart';
import 'package:galmax/utils/client_manager.dart';
import 'package:galmax/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:universal_html/html.dart' as html;

import 'cipher.dart';
import 'sqlcipher_stub.dart'
    if (dart.library.io) 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

Future<DatabaseApi> flutterMatrixSdkDatabaseBuilder(String clientName) async {
  MatrixSdkDatabase? database;
  Object? lastError;
  StackTrace? lastStackTrace;
  // Открытие может споткнуться о транзитный лок: базу одновременно
  // трогают два изолята (UI + фон-синк/FCM-хендлер). Ретраим с бэкоффом
  // и только потом считаем базу мёртвой — раньше один случайный лок
  // вёл сразу к УДАЛЕНИЮ файла базы и «перелогину».
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
    }
    try {
      database = await _constructDatabase(clientName);
      await database.open();
      return database;
    } catch (e, s) {
      lastError = e;
      lastStackTrace = s;
      Logs().w(
        'Database open failed (attempt ${attempt + 1}/3) for $clientName',
        e,
        s,
      );
    }
  }
  Logs().wtf('Unable to construct database!', lastError, lastStackTrace);

  try {
    // Send error notification:
    final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
    ClientManager.sendInitNotification(
      l10n.initAppError,
      lastError.toString(),
    );
  } catch (e, s) {
    Logs().e('Unable to send error notification', e, s);
  }

  // Try to delete database so that it can created again on next init:
  database?.delete().catchError(
    (e, s) => Logs().wtf(
      'Unable to delete database, after failed construction',
      e,
      s,
    ),
  );

  // Delete database file:
  if (!kIsWeb) {
    final dbFile = File(await _getDatabasePath(clientName));
    if (await dbFile.exists()) await dbFile.delete();
  }

  throw lastError!;
}

Future<MatrixSdkDatabase> _constructDatabase(String clientName) async {
  if (kIsWeb) {
    html.window.navigator.storage?.persist();
    return await MatrixSdkDatabase.init(clientName);
  }

  final cipher = await getDatabaseCipher();

  Directory? fileStorageLocation;
  try {
    final temporaryDirectory = await getTemporaryDirectory();
    fileStorageLocation = await Directory(
      join(temporaryDirectory.path, 'galmax_download_cache'),
    ).create(recursive: true);
  } on MissingPlatformDirectoryException catch (_) {
    Logs().w(
      'No temporary directory for file cache available on this platform.',
    );
  }

  final path = await _getDatabasePath(clientName);

  // fix dlopen for old Android
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  // import the SQLite / SQLCipher shared objects / dynamic libraries
  final factory = createDatabaseFactoryFfi(
    ffiInit: SQfLiteEncryptionHelper.ffiInit,
  );

  // required for [getDatabasesPath]
  databaseFactory = factory;

  // migrate from potential previous SQLite database path to current one
  await _migrateLegacyLocation(path, clientName);

  // in case we got a cipher, we use the encryption helper
  // to manage SQLite encryption
  final helper = cipher == null
      ? null
      : SQfLiteEncryptionHelper(factory: factory, path: path, cipher: cipher);

  // check whether the DB is already encrypted and otherwise do so
  await helper?.ensureDatabaseFileEncrypted();

  final database = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      // most important : apply encryption when opening the DB
      onConfigure: (db) async {
        await helper?.applyPragmaKey(db);
        // WAL: читатели не блокируют писателя — два изолята (UI +
        // фон-синк/FCM) уживаются в одном файле. busy_timeout: вместо
        // мгновенного 'database is locked' ждём освобождения до 10с.
        // Без этого случайный лок вёл к удалению базы и «перелогину».
        try {
          await db.execute('PRAGMA journal_mode=WAL;');
        } catch (_) {}
        try {
          await db.execute('PRAGMA busy_timeout=10000;');
        } catch (_) {}
      },
    ),
  );

  return await MatrixSdkDatabase.init(
    clientName,
    database: database,
    maxFileSize: 1000 * 1000 * 10,
    fileStorageLocation: fileStorageLocation?.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
  );
}

Future<String> _getDatabasePath(String clientName) async {
  final databaseDirectory = PlatformInfos.isIOS || PlatformInfos.isMacOS
      ? await getLibraryDirectory()
      : await getApplicationSupportDirectory();

  return join(databaseDirectory.path, '$clientName.sqlite');
}

Future<void> _migrateLegacyLocation(
  String sqlFilePath,
  String clientName,
) async {
  final oldPath = PlatformInfos.isDesktop
      ? (await getApplicationSupportDirectory()).path
      : await getDatabasesPath();

  final oldFilePath = join(oldPath, clientName);
  if (oldFilePath == sqlFilePath) return;

  final maybeOldFile = File(oldFilePath);
  if (await maybeOldFile.exists()) {
    Logs().i(
      'Migrate legacy location for database from "$oldFilePath" to "$sqlFilePath"',
    );
    await maybeOldFile.copy(sqlFilePath);
    await maybeOldFile.delete();
  }
}
