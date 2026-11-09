import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'core/bill_file.dart';
import 'core/db.dart';
import 'core/debug_hooks.dart';
import 'core/settings.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await AppPaths.init();
  await AppDb.open();
  await Settings.instance.load();

  const options = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(1180, 720),
    center: true,
    title: 'MedBillings',
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Double-clicking a .mbill file (Windows/Linux) passes its path as an argument.
  final billFile = args.where((a) => a.toLowerCase().endsWith('.${BillFile.extension}')).firstOrNull;
  registerDebugHooks();
  runApp(MedBillingsApp(openBillFile: billFile));
}

class MedBillingsApp extends StatelessWidget {
  const MedBillingsApp({super.key, this.openBillFile});
  final String? openBillFile;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) => MaterialApp(
        title: 'MedBillings',
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: Settings.instance.themeMode,
        locale: const Locale('en', 'IN'),
        supportedLocales: const [Locale('en', 'IN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AppShell(openBillFile: openBillFile),
        builder: (context, child) => RepaintBoundary(key: appBoundaryKey, child: child),
      ),
    );
  }
}
