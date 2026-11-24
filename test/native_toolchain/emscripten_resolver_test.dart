// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/emscripten.dart';
import 'package:native_toolchain_cmake/src/tool/tool.dart';
import 'package:native_toolchain_cmake/src/tool/tool_instance.dart';
import 'package:test/test.dart';

void main() {
  test('discovers emcc in the documented order', () async {
    final temp = await Directory.systemTemp.createTemp('ntc_emcc_order_');
    addTearDown(() => temp.delete(recursive: true));

    final exe = OS.current.executableFileName('emcc');
    Future<Uri> write(String relative) async {
      final file = File.fromUri(temp.uri.resolve(relative));
      await file.parent.create(recursive: true);
      await file.writeAsString('#!/bin/sh\nexit 1\n');
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', file.path]);
      }
      return file.uri.normalizePath();
    }

    final explicitRoot = await write('explicit-root/$exe');
    final emsdkRoot = await write('emsdk/upstream/emscripten/$exe');
    final pathRoot = await write('path/$exe');
    final envEmsdk = await write('env-emsdk/upstream/emscripten/$exe');

    final pathValue = Platform.isWindows
        ? '${temp.uri.resolve('path').toFilePath()};C:/Windows/System32'
        : '${temp.uri.resolve('path').toFilePath()}:/usr/bin:/bin';

    final config = UserConfig(
      targetOS: webOS,
      emscriptenRoot: explicitRoot.resolve('.').toFilePath(),
      emsdkPath: temp.uri.resolve('emsdk').toFilePath(),
      envVarAndroidHomeAsDefault: false,
    );
    final candidates = await emcc.defaultResolver!.resolve(
      userConfig: config,
      logger: null,
      environment: {
        'PATH': pathValue,
        'EMSDK': temp.uri.resolve('env-emsdk').toFilePath(),
        'HOME': temp.uri.resolve('home').toFilePath(),
        'USERPROFILE': temp.uri.resolve('home').toFilePath(),
      },
    );

    // Resolve symlinks before comparing: on Windows the temp directory can be
    // exposed as an 8.3 short name (RUNNER~1) and on macOS /var is a symlink
    // to /private/var, so raw URIs legitimately differ.
    Future<String> canonical(Uri uri) async {
      final path = await File.fromUri(uri).resolveSymbolicLinks();
      return Platform.isWindows ? path.toLowerCase() : path;
    }

    final found = await Future.wait(candidates.map((e) => canonical(e.uri)));
    final expected = await Future.wait([explicitRoot, emsdkRoot, pathRoot, envEmsdk].map(canonical));
    expect(found, containsAll(expected));
    expect(found.length, greaterThanOrEqualTo(expected.length));
    expect(found.sublist(0, expected.length), expected);
  });

  group('finds Emscripten.cmake', () {
    const toolchainSuffix = 'cmake/Modules/Platform/Emscripten.cmake';

    /// Creates a fake installation with [emccRelative] as the emcc binary and
    /// [toolchainRelative] as Emscripten.cmake, then resolves the toolchain
    /// file from that emcc.
    Future<Uri> resolve(String emccRelative, String? toolchainRelative) async {
      final temp = await Directory.systemTemp.createTemp('ntc_emcc_layout_');
      addTearDown(() => temp.delete(recursive: true));

      Future<Uri> write(String relative) async {
        final file = File.fromUri(temp.uri.resolve(relative));
        await file.parent.create(recursive: true);
        await file.writeAsString('stub');
        return file.uri;
      }

      final emccUri = await write(emccRelative);
      if (toolchainRelative != null) {
        await write(toolchainRelative);
      }

      final toolchainFile = await findEmscriptenToolchainFile(
        emccInstance: ToolInstance(tool: Tool(name: 'Emscripten emcc'), uri: emccUri),
      );
      return toolchainFile.normalizePath();
    }

    test('emsdk layout (root next to emcc)', () async {
      final found = await resolve('emsdk/upstream/emscripten/emcc', 'emsdk/upstream/emscripten/$toolchainSuffix');
      expect(found.pathSegments.last, 'Emscripten.cmake');
      expect(found.path, endsWith('upstream/emscripten/$toolchainSuffix'));
    });

    test('Homebrew layout (root is libexec)', () async {
      // Homebrew: Cellar/emscripten/<version>/bin/emcc wrapper next to
      // Cellar/emscripten/<version>/libexec/cmake/Modules/Platform/Emscripten.cmake.
      final found = await resolve('Cellar/emscripten/7.0.1/bin/emcc', 'Cellar/emscripten/7.0.1/libexec/$toolchainSuffix');
      expect(found.path, endsWith('Cellar/emscripten/7.0.1/libexec/$toolchainSuffix'));
    });

    test('library layout (root under lib/emscripten)', () async {
      final found = await resolve('usr/bin/emcc', 'usr/lib/emscripten/$toolchainSuffix');
      expect(found.path, endsWith('usr/lib/emscripten/$toolchainSuffix'));
    });
  });
}
