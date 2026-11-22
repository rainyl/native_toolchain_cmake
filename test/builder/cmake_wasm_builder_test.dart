// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final sourceDir = Directory('test/builder/testfiles/wasm').absolute.uri;

  Future<bool> emscriptenAvailable() async {
    final instances = await emcc.defaultResolver!.resolve(logger: logger);
    return instances.isNotEmpty;
  }

  group('CMakeWasmBuilder', () {
    late bool available;
    setUpAll(() async {
      available = await emscriptenAvailable();
      if (!available) {
        // ignore: avoid_print
        print('Skipping Emscripten tests: emcc not found. Set EMSDK or add emsdk to PATH.');
      }
    });

    test('standalone build emits js and wasm', () async {
      if (!available) return;
      final temp = await tempDirForTest();
      final builder = CMakeWasmBuilder.create(name: 'add', sourceDir: sourceDir, logger: logger);

      final files = await builder.runStandalone(outputDirectory: temp);
      final names = files.map((e) => e.pathSegments.last).toSet();

      expect(names, containsAll(<String>['add.js', 'add.wasm']));
      final wasm = File.fromUri(files.firstWhere((e) => e.path.endsWith('.wasm')));
      expect(await wasm.length(), greaterThan(0));
      final bytes = await wasm.readAsBytes();
      expect(bytes.take(4).toList(), [0x00, 0x61, 0x73, 0x6D]);
    });

    test('standalone singleFile emits only js', () async {
      if (!available) return;
      final temp = await tempDirForTest();
      final builder = CMakeWasmBuilder.create(
        name: 'add',
        sourceDir: sourceDir,
        singleFile: true,
        logger: logger,
      );

      final files = await builder.runStandalone(outputDirectory: temp);
      final names = files.map((e) => e.pathSegments.last).toSet();

      expect(names, contains('add.js'));
      expect(names, isNot(contains('add.wasm')));
      expect(await File.fromUri(files.single).length(), greaterThan(0));
    });

    test('reuses the build directory when switching singleFile modes', () async {
      if (!available) return;
      final temp = await tempDirForTest();

      final separate = CMakeWasmBuilder.create(name: 'add', sourceDir: sourceDir, logger: logger);
      await separate.runStandalone(outputDirectory: temp);
      expect(File.fromUri(temp.resolve('add.wasm')).existsSync(), isTrue);

      final single = CMakeWasmBuilder.create(
        name: 'add',
        sourceDir: sourceDir,
        singleFile: true,
        logger: logger,
      );
      await single.runStandalone(outputDirectory: temp);
      expect(File.fromUri(temp.resolve('add.wasm')).existsSync(), isFalse);

      // CMakeCache.txt previously retained -sSINGLE_FILE=1 here.
      await separate.runStandalone(outputDirectory: temp);
      expect(File.fromUri(temp.resolve('add.wasm')).existsSync(), isTrue);
    });

    test('hook mode emits two data assets', () async {
      if (!available) return;
      final temp = await tempDirForTest();
      final shared = temp.resolve('shared/');
      final builder = BuildInputBuilder()
        ..setupShared(
          packageName: 'add',
          packageRoot: temp,
          outputFile: temp.resolve('output.json'),
          outputDirectoryShared: shared,
        )
        ..config.setupBuild(linkingEnabled: false)
        ..addExtension(DataAssetsExtension());
      final input = BuildInput(builder.json);
      final output = BuildOutputBuilder();

      final wasmBuilder = CMakeWasmBuilder.create(name: 'add', sourceDir: sourceDir, logger: logger);
      await wasmBuilder.run(input: input, output: output);

      final assets = output.build().assets.data;
      expect(assets, hasLength(2));
      expect(assets.map((a) => a.name), containsAll(<String>['wasm/add.js', 'wasm/add.wasm']));
      for (final asset in assets) {
        expect(await File.fromUri(asset.file).exists(), isTrue);
      }

      final encodedOutput = jsonEncode(output.json);
      expect(encodedOutput, contains('emscripten'));
      expect(encodedOutput, contains('toolchain_file'));
    });

    test('native targets skip the wasm build', () async {
      final temp = await tempDirForTest();
      final shared = temp.resolve('shared/');
      final builder = BuildInputBuilder()
        ..setupShared(
          packageName: 'add',
          packageRoot: temp,
          outputFile: temp.resolve('output.json'),
          outputDirectoryShared: shared,
        )
        ..config.setupBuild(linkingEnabled: false)
        ..addExtension(
          CodeAssetExtension(
            targetOS: OS.current,
            targetArchitecture: Architecture.current,
            linkModePreference: LinkModePreference.dynamic,
          ),
        )
        ..addExtension(DataAssetsExtension());
      final input = BuildInput(builder.json);
      final output = BuildOutputBuilder();

      final wasmBuilder = CMakeWasmBuilder.create(name: 'add', sourceDir: sourceDir, logger: logger);
      await wasmBuilder.run(input: input, output: output);

      expect(output.build().assets.data, isEmpty);
    });
  });
}
