import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'screens/database_startup.dart';

class PrmApp extends StatelessWidget {
  const PrmApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ANH EM QUÁN • Nhân sự',
    theme: buildAppTheme(),
    home: const DatabaseStartup(),
  );
}
