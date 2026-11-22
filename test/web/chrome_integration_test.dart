// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

void main() {
  Directory? work;
  HttpServer? server;
  String? chrome;
  final requests = <String>[];
  var available = false;

  setUpAll(() async {
    chrome = _findChrome();
    final emccInstances = await emcc.defaultResolver!.resolve(logger: null);
    if (chrome == null || emccInstances.isEmpty) {
      if (Platform.environment['NTC_REQUIRE_CHROME'] == '1') {
        throw StateError(
          'Chrome integration test requires both Chrome and emcc. '
          'Chrome: ${chrome ?? 'not found'}. emcc candidates: ${emccInstances.length}.',
        );
      }
      return;
    }

    work = await Directory.systemTemp.createTemp('ntc_chrome_');
    final builder = CMakeWasmBuilder.create(
      name: 'add',
      sourceDir: Directory('test/builder/testfiles/wasm').absolute.uri,
    );
    await builder.runStandalone(outputDirectory: work!.uri);

    final fixture = File('${Directory.current.path}/.dart_tool/ntc_chrome_fixture.dart');
    await fixture.writeAsString(_loaderSource);
    final compile = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-O1',
      '-o',
      work!.uri.resolve('main.dart.js').toFilePath(),
      fixture.path,
    ], workingDirectory: Directory.current.path);
    await fixture.delete();
    if (compile.exitCode != 0) {
      throw TestFailure('dart compile js failed:\n${compile.stdout}\n${compile.stderr}');
    }

    await File.fromUri(work!.uri.resolve('index.html')).writeAsString(_html);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) {
      requests.add('${request.method} ${request.uri}');
      _serve(request, work!);
    });
    available = true;
  });

  tearDownAll(() async {
    await server?.close(force: true);
    if (work != null && await work!.exists()) {
      await work!.delete(recursive: true);
    }
  });

  test('loads an Emscripten module in Chrome', () async {
    if (!available) {
      markTestSkipped('Chrome or emcc not available');
      return;
    }

    final profile = await Directory.systemTemp.createTemp('ntc_chrome_profile_');
    final result = await Process.run(
      chrome!,
      [
        '--headless=new',
        '--disable-gpu',
        '--no-sandbox',
        '--disable-dev-shm-usage',
        '--user-data-dir=${profile.path}',
        '--virtual-time-budget=20000',
        '--dump-dom',
        'http://127.0.0.1:${server!.port}/',
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    await profile.delete(recursive: true);

    final diagnostics = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: diagnostics);
    expect(result.stdout, contains('RESULT:5'), reason: diagnostics);
  });
}

const _html = '''
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>native_toolchain_cmake wasm test</title></head>
  <body>
    <!-- Preload the Emscripten factory; the loader below detects it and skips
         dynamic script injection, which makes headless runs deterministic. -->
    <script src="add.js"></script>
    <script src="main.dart.js"></script>
  </body>
</html>
''';

const _loaderSource = r'''
import 'package:native_toolchain_cmake/web.dart';
import 'package:web/web.dart';

Future<void> main() async {
  try {
    final module = await loadEmscriptenModule(
      scriptUrl: Uri.base.resolve('add.js'),
      factoryName: 'addModule',
    );
    final value = module.callNum('add', args: [2, 3]);
    document.body!.textContent = 'RESULT:$value';
  } catch (error) {
    document.body!.textContent = 'ERROR:$error';
  }
}
''';

Future<void> _serve(HttpRequest request, Directory root) async {
  final path = request.uri.path;
  final name = path == '/' ? 'index.html' : path.substring(1);
  final file = File.fromUri(root.uri.resolve(name));
  if (!await file.exists()) {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
    return;
  }

  request.response.headers.contentType = switch (name.split('.').last) {
    'html' => ContentType.html,
    'js' => ContentType('application', 'javascript', charset: 'utf-8'),
    'wasm' => ContentType('application', 'wasm'),
    _ => ContentType.binary,
  };
  request.response.add(await file.readAsBytes());
  await request.response.close();
}

String? _findChrome() {
  final fromEnv = Platform.environment['CHROME_EXECUTABLE'];
  if (fromEnv != null && fromEnv.isNotEmpty && File(fromEnv).existsSync()) {
    return fromEnv;
  }

  final candidates = <String>[
    if (Platform.isWindows) ...[
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    ],
    if (Platform.isMacOS) '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    if (Platform.isLinux) ...[
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/opt/google/chrome/chrome',
    ],
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }

  final which = Platform.isWindows ? 'where' : 'which';
  for (final name in ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser', 'chrome']) {
    try {
      final result = Process.runSync(which, [name], stdoutEncoding: utf8);
      if (result.exitCode != 0) continue;
      final path = (result.stdout as String).split('\n').first.trim();
      if (path.isNotEmpty && File(path).existsSync()) return path;
    } on ProcessException {
      // Not on PATH.
    }
  }
  return null;
}
