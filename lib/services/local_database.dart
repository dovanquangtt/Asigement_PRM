import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sample_data.dart';

/// Database SQLite riêng của thiết bị, sao chép từ asset đúng một lần.
class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();
  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final filename = p.join(directory.path, 'prm_database.db');
      final factory = Platform.isWindows || Platform.isLinux
          ? _desktopFactory()
          : mobile.databaseFactory;
      return await openBundledDatabase(factory, filename);
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static DatabaseFactory _desktopFactory() {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  /// Factory và đường dẫn truyền vào để kiểm tra cùng luồng mở file thật.
  static Future<Database> openBundledDatabase(
    DatabaseFactory factory,
    String filename,
  ) async {
    if (!await factory.databaseExists(filename)) {
      final bytes = await rootBundle.load('database/prm_database.db');
      final target = File(filename);
      await target.parent.create(recursive: true);
      final temporary = File('$filename.installing');
      await temporary.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      await temporary.rename(filename);
    }
    final db = await factory.openDatabase(
      filename,
      options: OpenDatabaseOptions(
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    try {
      await installSampleData(db);
      return db;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }
}
