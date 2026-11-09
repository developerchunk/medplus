import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../ui/nav.dart';

/// Debug-build-only VM service extensions used to inspect the running app:
///   ext.medbillings.screenshot?path=/tmp/x.png
///   ext.medbillings.nav?page=1
///   ext.medbillings.template?code=1
final appBoundaryKey = GlobalKey();
final appNavigatorKey = GlobalKey<NavigatorState>();

void registerDebugHooks() {
  if (!kDebugMode) return;
  developer.registerExtension('ext.medbillings.screenshot', (method, params) async {
    final boundary = appBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return developer.ServiceExtensionResponse.error(1, 'no boundary');
    final image = await boundary.toImage(pixelRatio: double.tryParse(params['ratio'] ?? '') ?? 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(params['path']!).writeAsBytes(bytes!.buffer.asUint8List());
    return developer.ServiceExtensionResponse.result(jsonEncode({'ok': true}));
  });
  developer.registerExtension('ext.medbillings.nav', (method, params) async {
    Nav.go(int.parse(params['page']!));
    return developer.ServiceExtensionResponse.result(jsonEncode({'ok': true}));
  });
  developer.registerExtension('ext.medbillings.pop', (method, params) async {
    appNavigatorKey.currentState?.maybePop();
    return developer.ServiceExtensionResponse.result(jsonEncode({'ok': true}));
  });
  developer.registerExtension('ext.medbillings.customer', (method, params) async {
    Nav.billForCustomer(int.parse(params['id']!));
    return developer.ServiceExtensionResponse.result(jsonEncode({'ok': true}));
  });
  developer.registerExtension('ext.medbillings.template', (method, params) async {
    Nav.billWithTemplate(params['code']!);
    return developer.ServiceExtensionResponse.result(jsonEncode({'ok': true}));
  });
}
