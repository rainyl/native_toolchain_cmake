// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('windows')
@OnPlatform({
  'windows': Timeout.factor(10),
})
library;

import 'dart:io';

import 'package:change_case/change_case.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/msvc.dart';
import 'package:native_toolchain_cmake/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() async {
  if (!Platform.isWindows) {
    // Avoid needing status files on Dart SDK CI.
    return;
  }

  final targetOS = OS.current;

  const targets = [
    Architecture.arm64,
    Architecture.ia32,
    Architecture.x64,
  ];

  late Uri dumpbinUri;

  setUp(() async {
    dumpbinUri = (await dumpbin.defaultResolver!.resolve(logger: logger)).first.uri;
  });

  const dumpbinMachine = {
    Architecture.arm64: 'ARM64',
    Architecture.ia32: 'x86',
    Architecture.x64: 'x64',
  };

  var selectBuildMode = 0;

  final dumpbinFileType = {
    DynamicLoadingBundled(): 'DLL',
    StaticLinking(): 'LIBRARY',
  };

  for (final linkMode in [DynamicLoadingBundled()]) {
    for (final target in targets) {
      // Cycle through all optimization levels.
      final buildMode = BuildMode.values[selectBuildMode];
      selectBuildMode = (selectBuildMode + 1) % BuildMode.values.length;
      test('CMakeBuilder $linkMode library $target $buildMode', () async {
        final tempUri = await tempDirForTest();
        final tempUri2 = await tempDirForTest();
        const name = 'add';

        final buildInputBuilder = BuildInputBuilder()
          ..setupShared(
            packageName: name,
            packageRoot: tempUri,
            outputFile: tempUri.resolve('output.json'),
            outputDirectory: tempUri,
            outputDirectoryShared: tempUri2,
          )
          ..config.setupBuild(
            linkingEnabled: false,
            dryRun: false,
          )
          ..config.setupShared(buildAssetTypes: [CodeAsset.type])
          ..config.setupCode(
            targetOS: OS.windows,
            targetArchitecture: target,
            linkModePreference:
                linkMode == DynamicLoadingBundled() ? LinkModePreference.dynamic : LinkModePreference.static,
          );

        final buildInput = BuildInput(buildInputBuilder.json);
        final buildOutput = BuildOutputBuilder();

        final cbuilder = CMakeBuilder.create(
          name: name,
          sourceDir: Directory('test/builder/testfiles/add').uri,
          buildMode: buildMode,
        );
        await cbuilder.run(
          input: buildInput,
          output: buildOutput,
          logger: logger,
        );

        final libUri = switch (targetOS) {
          OS.windows =>
            tempUri.resolve('${buildMode.name.toCapitalCase()}/${OS.current.dylibFileName(name)}'),
          _ => tempUri.resolve(OS.current.dylibFileName(name)),
        };
        expect(await File.fromUri(libUri).exists(), true);
        final result = await runProcess(
          executable: dumpbinUri,
          arguments: ['/HEADERS', libUri.toFilePath()],
          logger: logger,
        );
        expect(result.exitCode, 0);
        final machine = result.stdout.split('\n').firstWhere((e) => e.contains('machine'));
        expect(machine, contains(dumpbinMachine[target]));
        final fileType = result.stdout.split('\n').firstWhere((e) => e.contains('File Type'));
        expect(fileType, contains(dumpbinFileType[linkMode]));
      });
    }
  }
}
