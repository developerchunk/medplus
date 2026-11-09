import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// macOS only draws frames for windows that are on screen. If the test app opens on another
/// desktop (Space) or behind the window you're working in, every pump waits forever.
/// Bring the test window onto the current desktop at the app's normal size and keep it on top.
Future<void> keepTestWindowVisible() async {
  await windowManager.ensureInitialized();
  // Tests skip main(), so apply the app's normal window size here.
  await windowManager.setMinimumSize(const Size(1180, 720));
  await windowManager.setSize(const Size(1440, 900));
  await windowManager.center();
  await windowManager.setVisibleOnAllWorkspaces(true);
  await windowManager.setAlwaysOnTop(true);
  await windowManager.show();
  await windowManager.focus();
}
