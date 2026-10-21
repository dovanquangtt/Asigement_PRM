import 'package:flutter/material.dart';

import '../services/local_database.dart';
import 'login_screen.dart';

class DatabaseStartup extends StatefulWidget {
  const DatabaseStartup({super.key});

  @override
  State<DatabaseStartup> createState() => _DatabaseStartupState();
}

class _DatabaseStartupState extends State<DatabaseStartup> {
  late Future<void> opening;

  @override
  void initState() {
    super.initState();
    opening = initialize();
  }

  Future<void> initialize() async {
    final db = await LocalDatabase.instance.database;
    // Truy vấn thật để phát hiện file sai cấu trúc trước khi vào ứng dụng.
    await db.query('roles', columns: ['id', 'code', 'name']);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: opening,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Không mở được database cục bộ.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() {
                    opening = initialize();
                  }),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return const LoginPage();
    },
  );
}
