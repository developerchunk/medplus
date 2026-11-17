import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'db.dart';

enum UpdateStage { idle, checking, upToDate, downloading, ready, installing, failed }

/// A version like 1.2.3+4 (pubspec) or 1.2.3-4 (Debian package).
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts, this.build);
  final List<int> parts; // major, minor, patch
  final int build;

  static AppVersion? parse(String s) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[+-](\d+))?').firstMatch(s.trim());
    if (m == null) return null;
    return AppVersion([int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)], int.tryParse(m[4] ?? '') ?? 0);
  }

  @override
  int compareTo(AppVersion o) {
    for (var i = 0; i < 3; i++) {
      final c = parts[i].compareTo(o.parts[i]);
      if (c != 0) return c;
    }
    return build.compareTo(o.build);
  }

  bool operator >(AppVersion o) => compareTo(o) > 0;

  @override
  String toString() => parts.join('.');
}

/// Keeps MedBillings up to date from the GitHub releases of [repo] (Linux shop PC).
///
/// Every few hours it looks at the latest release; when it is newer it downloads
/// the .deb and its signature in the background and reports [UpdateStage.ready].
/// [install] then runs the root helper through pkexec (no password for the
/// logged-in user, see linux/packaging), which only accepts a .deb signed with
/// the MedBillings release key. [relaunch] closes the database and starts the
/// new version.
class Updater extends ChangeNotifier {
  Updater._();
  static final instance = Updater._();

  static const repo = 'developerchunk/medplus';
  static const helper = '/opt/medbillings/updater/medbillings-update';
  static const installedBinary = '/opt/medbillings/MedBillings';
  static const checkEvery = Duration(hours: 6);

  UpdateStage stage = UpdateStage.idle;
  AppVersion? current;
  String currentLabel = '';
  AppVersion? latest;
  String releaseNotes = '';
  String? error;
  double progress = 0;
  DateTime? lastChecked;
  File? _deb, _sig;
  Timer? _timer;

  /// Automatic updates work on the installed Linux app (the shop PC).
  bool get supported => Platform.isLinux && File(helper).existsSync();
  bool get ready => stage == UpdateStage.ready;

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      currentLabel = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
      current = AppVersion.parse(currentLabel);
    } catch (_) {}
    notifyListeners();
    if (!supported) return;
    // First look shortly after start (not during it), then every few hours.
    Timer(const Duration(seconds: 30), check);
    _timer = Timer.periodic(checkEvery, (_) => check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _set(UpdateStage s, {String? err}) {
    stage = s;
    error = err;
    notifyListeners();
  }

  /// Looks for a newer release and downloads it. Quiet on network errors unless [manual].
  Future<void> check({bool manual = false}) async {
    if (!supported || current == null) return;
    if (stage == UpdateStage.checking || stage == UpdateStage.downloading || stage == UpdateStage.installing) return;
    if (stage == UpdateStage.ready && !manual) return;
    _set(UpdateStage.checking);
    try {
      final rel = await _getJson('https://api.github.com/repos/$repo/releases/latest');
      lastChecked = DateTime.now();
      final assets = ((rel['assets'] as List?) ?? []).cast<Map>();
      Map? deb;
      for (final a in assets) {
        final name = '${a['name']}';
        if (name.startsWith('medbillings_') && name.endsWith('_amd64.deb')) deb = a;
      }
      final sig = deb == null ? null : assets.where((a) => a['name'] == '${deb!['name']}.sig').firstOrNull;
      // medbillings_1.2.0-3_amd64.deb -> 1.2.0+3
      final version = deb == null ? null : AppVersion.parse('${deb['name']}'.split('_')[1]);
      if (deb == null || sig == null || version == null || !(version > current!)) {
        _set(UpdateStage.upToDate);
        return;
      }
      latest = version;
      releaseNotes = '${rel['body'] ?? ''}'.trim();
      _set(UpdateStage.downloading);
      progress = 0;
      final dir = Directory(p.join(_cacheDir(), 'updates'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // Drop older downloads.
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.contains('${deb['name']}')) f.deleteSync();
      }
      final debFile = File(p.join(dir.path, '${deb['name']}'));
      final sigFile = File(p.join(dir.path, '${sig['name']}'));
      final size = (deb['size'] as num?)?.toInt() ?? 0;
      if (!debFile.existsSync() || debFile.lengthSync() != size) {
        await _download('${deb['browser_download_url']}', debFile, size);
      }
      await _download('${sig['browser_download_url']}', sigFile, 0);
      if (size > 0 && debFile.lengthSync() != size) throw const HttpException('download incomplete');
      _deb = debFile;
      _sig = sigFile;
      _set(UpdateStage.ready);
    } catch (e) {
      _set(manual ? UpdateStage.failed : UpdateStage.idle, err: _friendly(e));
    }
  }

  /// Installs the downloaded update. Returns null on success, or what went wrong.
  Future<String?> install() async {
    final deb = _deb, sig = _sig;
    if (deb == null || sig == null || !deb.existsSync()) return 'The update file is missing. Check for updates again.';
    _set(UpdateStage.installing);
    try {
      final r = await Process.run('pkexec', [helper, deb.path, sig.path]);
      if (r.exitCode == 0) return null;
      final msg = switch (r.exitCode) {
        126 || 127 => 'Permission to install was not given.',
        3 => 'The update file failed its safety check (signature). It was not installed.',
        5 => 'This version is already installed.',
        _ => 'Install failed (${r.exitCode}): ${'${r.stderr}'.trim().split('\n').last}',
      };
      _set(UpdateStage.ready, err: msg);
      return msg;
    } catch (e) {
      _set(UpdateStage.ready, err: '$e');
      return 'Could not start the installer: $e';
    }
  }

  /// Closes the database and starts the newly installed version once this one has exited.
  Future<Never> relaunch() async {
    await AppDb.close();
    await Process.start('/bin/sh', ['-c', 'while kill -0 $pid 2>/dev/null; do sleep 0.3; done; exec "$installedBinary"'], mode: ProcessStartMode.detached);
    exit(0);
  }

  // ------------------------------------------------------------ http

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'MedBillings-updater';

  static Future<Map<String, dynamic>> _getJson(String url) async {
    final c = _client();
    try {
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return {}; // no release published yet
      if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      c.close();
    }
  }

  Future<void> _download(String url, File to, int size) async {
    final c = _client();
    final part = File('${to.path}.part');
    try {
      final res = await (await c.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) throw HttpException('download answered ${res.statusCode}');
      final sink = part.openWrite();
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (size > 0) {
          progress = got / size;
          notifyListeners();
        }
      }
      await sink.close();
      if (to.existsSync()) to.deleteSync();
      part.renameSync(to.path);
    } finally {
      c.close();
      if (part.existsSync()) part.deleteSync();
    }
  }

  static String _cacheDir() {
    final xdg = Platform.environment['XDG_CACHE_HOME'];
    final home = Platform.environment['HOME'] ?? AppPaths.root.path;
    return p.join(xdg != null && xdg.isNotEmpty ? xdg : p.join(home, '.cache'), 'medbillings');
  }

  static String _friendly(Object e) {
    if (e is SocketException || e is TimeoutException) return 'No internet connection.';
    return '$e';
  }
}
