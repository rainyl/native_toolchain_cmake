// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/emscripten.dart';
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

    final found = candidates.map((e) => e.uri).toList();
    expect(found, containsAll(<Uri>[explicitRoot, emsdkRoot, pathRoot, envEmsdk]));

    final firstFour = found.take(4).toList();
    expect(firstFour[0], explicitRoot);
    expect(firstFour[1], emsdkRoot);
    expect(firstFour[2], pathRoot);
    expect(firstFour[3], envEmsdk);
  });
}
