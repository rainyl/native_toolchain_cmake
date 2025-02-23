// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('mac-os')
@OnPlatform({
  'mac-os': Timeout.factor(2),
})
library;

import 'dart:io';

import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  if (!Platform.isMacOS) {
    // Avoid needing status files on Dart SDK CI.
    return;
  }

  const targets = [
    Architecture.arm64,
    Architecture.x64,
  ];

  // Dont include 'mach-o' or 'Mach-O', different spelling is used.
  const objdumpFileFormat = {
    Architecture.arm64: 'arm64',
    Architecture.x64: '64-bit x86-64',
  };

  for (final target in targets) {
    test('CMakeBuilder library $target', () async {
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
          targetOS: OS.macOS,
          targetArchitecture: target,
          linkModePreference: LinkModePreference.dynamic,
          cCompiler: cCompiler,
          macOS: MacOSCodeConfig(targetVersion: defaultMacOSVersion),
        );
      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      final cbuilder = CMakeBuilder.create(
        name: name,
        sourceDir: Directory('test/builder/testfiles/add').uri,
        buildMode: BuildMode.release,
      );
      await cbuilder.run(
        input: buildInput,
        output: buildOutput,
        logger: logger,
      );

      final libUri = tempUri.resolve(OS.macOS.libraryFileName(name, DynamicLoadingBundled()));
      final result = await runProcess(
        executable: Uri.file('objdump'),
        arguments: ['-t', libUri.path],
        logger: logger,
      );
      expect(result.exitCode, 0);
      final machine = result.stdout.split('\n').firstWhere((e) => e.contains('file format'));
      expect(machine, contains(objdumpFileFormat[target]));
    });
  }

  const flutterMacOSLowestBestEffort = 12;
  const flutterMacOSLowestSupported = 13;

  for (final macosVersion in [flutterMacOSLowestBestEffort, flutterMacOSLowestSupported]) {
    test('macos min version $macosVersion', () async {
      const target = Architecture.arm64;
      final tempUri = await tempDirForTest();
      final out1Uri = tempUri.resolve('out1/');
      await Directory.fromUri(out1Uri).create();
      final out2Uri = tempUri.resolve('out2/');
      await Directory.fromUri(out1Uri).create();
      final lib1Uri = await buildLib(
        out1Uri,
        out2Uri,
        target,
        macosVersion,
      );

      final otoolResult = await runProcess(
        executable: Uri.file('otool'),
        arguments: ['-l', lib1Uri.path],
        logger: logger,
      );
      expect(otoolResult.exitCode, 0);
      expect(otoolResult.stdout, contains('minos $macosVersion.0'));
    });
  }
}

Future<Uri> buildLib(
  Uri tempUri,
  Uri tempUri2,
  Architecture targetArchitecture,
  int targetMacOSVersion,
) async {
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
      targetOS: OS.macOS,
      targetArchitecture: targetArchitecture,
      linkModePreference: LinkModePreference.dynamic,
      macOS: MacOSCodeConfig(targetVersion: targetMacOSVersion),
      cCompiler: cCompiler,
    );

  final buildInput = BuildInput(buildInputBuilder.json);
  final buildOutput = BuildOutputBuilder();

  final cbuilder = CMakeBuilder.create(
    name: name,
    sourceDir: Directory('test/builder/testfiles/add').uri,
    buildMode: BuildMode.release,
  );
  await cbuilder.run(
    input: buildInput,
    output: buildOutput,
    logger: logger,
  );

  final libUri = tempUri.resolve(OS.iOS.libraryFileName(name, DynamicLoadingBundled()));
  return libUri;
}
