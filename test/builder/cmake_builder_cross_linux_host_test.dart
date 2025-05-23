// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('linux')
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  if (!Platform.isLinux) {
    // Avoid needing status files on Dart SDK CI.
    return;
  }

  const targets = [
    Architecture.arm64,
    Architecture.x64,
    Architecture.riscv64,
  ];

  for (final linkMode in [DynamicLoadingBundled()]) {
    for (final target in targets) {
      test('CMakeBuilder $linkMode library $target', () async {
        final tempUri = await tempDirForTest();
        final tempUri2 = await tempDirForTest();
        const name = 'add';

        final buildInputBuilder = BuildInputBuilder()
          ..setupShared(
            packageName: name,
            packageRoot: tempUri,
            outputFile: tempUri.resolve('output.json'),
            outputDirectoryShared: tempUri2,
          )
          ..config.setupBuild(linkingEnabled: false)
          ..addExtension(
            CodeAssetExtension(
              targetOS: OS.linux,
              targetArchitecture: target,
              linkModePreference: linkMode == DynamicLoadingBundled()
                  ? LinkModePreference.dynamic
                  : LinkModePreference.static,
              cCompiler: cCompiler,
            ),
          );

        final buildInput = BuildInput(buildInputBuilder.json);
        final buildOutput = BuildOutputBuilder();

        final builder = CMakeBuilder.create(
          name: name,
          sourceDir: Directory('test/builder/testfiles/add').absolute.uri,
          buildMode: BuildMode.release,
        );
        await builder.run(
          input: buildInput,
          output: buildOutput,
          logger: logger,
        );

        final libUri = buildInput.outputDirectory.resolve(OS.linux.libraryFileName(name, linkMode));
        final machine = await readelfMachine(libUri.path);
        expect(machine, contains(readElfMachine[target]));
      });
    }
  }
}
