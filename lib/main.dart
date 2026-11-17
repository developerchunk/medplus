import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'core/bill_file.dart';
import 'core/db.dart';
import 'core/debug_hooks.dart';
import 'core/settings.dart';
import 'core/updater.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await AppPaths.init();
  await AppDb.open();
  await Settings.instance.load();
  await Updater.instance.init();

  // Fit the window to the screen: shop PCs often have 1366×768 or smaller monitors,
  // where a fixed 1440×900 window runs off the edge.
  final screen = await _screenSize();
  final roomy = screen == null || (screen.width >= 1500 && screen.height >= 940);
  final options = WindowOptions(
    size: roomy ? const Size(1440, 900) : screen,
    minimumSize: Size(screen == null || screen.width >= 1024 ? 1024 : screen.width, screen == null || screen.height >= 640 ? 640 : screen.height),
    center: true,
    title: 'MedBillings',
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    if (!roomy) await windowManager.maximize();
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

/// Usable size of the main screen (without the taskbar), or null if it can't be read.
Future<Size?> _screenSize() async {
  try {
    final d = await screenRetriever.getPrimaryDisplay();
    final s = d.visibleSize ?? d.size;
    return s.width > 0 && s.height > 0 ? s : null;
  } catch (_) {
    return null;
  }
}
