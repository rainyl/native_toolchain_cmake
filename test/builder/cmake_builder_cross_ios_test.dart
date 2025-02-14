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

const flutteriOSHighestBestEffort = 16;
const flutteriOSHighestSupported = 17;

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

  const name = 'add';

  for (final targetIOSSdk in IOSSdk.values) {
    for (final target in targets) {
      if (target == Architecture.x64 && targetIOSSdk == IOSSdk.iPhoneOS) {
        continue;
      }
      final libName = OS.iOS.libraryFileName(name, DynamicLoadingBundled());
      test('CMakeBuilder library $targetIOSSdk $target'.trim(), () async {
        final tempUri = await tempDirForTest();
        final tempUri2 = await tempDirForTest();

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
            targetOS: OS.iOS,
            targetArchitecture: target,
            linkModePreference: LinkModePreference.dynamic,
            iOS: IOSCodeConfig(
              targetSdk: targetIOSSdk,
              targetVersion: flutteriOSHighestBestEffort,
            ),
            cCompiler: cCompiler,
          );

        final buildInput = BuildInput(buildInputBuilder.json);
        final buildOutput = BuildOutputBuilder();

        final cbuilder = CMakeBuilder.create(
          name: name,
          sourceDir: 'test/builder/testfiles/add',
          buildMode: BuildMode.release,
        );
        await cbuilder.run(
          input: buildInput,
          output: buildOutput,
          logger: logger,
        );

        final libUri = tempUri.resolve(libName);
        final objdumpResult = await runProcess(
          executable: Uri.file('objdump'),
          arguments: ['-t', libUri.path],
          logger: logger,
        );
        expect(objdumpResult.exitCode, 0);
        final machine = objdumpResult.stdout.split('\n').firstWhere((e) => e.contains('file format'));
        expect(machine, contains(objdumpFileFormat[target]));

        final otoolResult = await runProcess(
          executable: Uri.file('otool'),
          arguments: ['-l', libUri.path],
          logger: logger,
        );
        expect(otoolResult.exitCode, 0);
        // As of native_assets_cli 0.10.0, the min target OS version is
        // always being passed in.
        expect(otoolResult.stdout, isNot(contains('LC_VERSION_MIN_IPHONEOS')));
        expect(otoolResult.stdout, contains('LC_BUILD_VERSION'));
        final platform = otoolResult.stdout.split('\n').firstWhere((e) => e.contains('platform'));
        if (targetIOSSdk == IOSSdk.iPhoneOS) {
          const platformIosDevice = 2;
          expect(platform, contains(platformIosDevice.toString()));
        } else {
          const platformIosSimulator = 7;
          expect(platform, contains(platformIosSimulator.toString()));
        }

        final libInstallName = await runOtoolInstallName(libUri, libName);
        expect(libInstallName, equals('@rpath/libadd.dylib'));
        final targetInstallName = '@executable_path/Frameworks/$libName';
        await runProcess(
          executable: Uri.file('install_name_tool'),
          arguments: [
            '-id',
            targetInstallName,
            libUri.toFilePath(),
          ],
          logger: logger,
        );
        final libInstallName2 = await runOtoolInstallName(libUri, libName);
        expect(libInstallName2, targetInstallName);
      });
    }
  }

  for (final iosVersion in [flutteriOSHighestBestEffort, flutteriOSHighestSupported]) {
    test('ios min version $iosVersion', () async {
      const target = Architecture.arm64;
      final tempUri = await tempDirForTest();
      final out1Uri = tempUri.resolve('out1/');
      await Directory.fromUri(out1Uri).create();
      final out2Uri = tempUri.resolve('out1/');
      await Directory.fromUri(out2Uri).create();
      final lib1Uri = await buildLib(
        out1Uri,
        out2Uri,
        target,
        iosVersion,
        DynamicLoadingBundled(),
      );

      final otoolResult = await runProcess(
        executable: Uri.file('otool'),
        arguments: ['-l', lib1Uri.path],
        logger: logger,
      );
      expect(otoolResult.exitCode, 0);
      expect(otoolResult.stdout, contains('minos $iosVersion.0'));
    });
  }
}

Future<Uri> buildLib(
  Uri tempUri,
  Uri tempUri2,
  Architecture targetArchitecture,
  int targetIOSVersion,
  LinkMode linkMode,
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
      targetOS: OS.iOS,
      targetArchitecture: targetArchitecture,
      linkModePreference:
          linkMode == DynamicLoadingBundled() ? LinkModePreference.dynamic : LinkModePreference.static,
      iOS: IOSCodeConfig(
        targetSdk: IOSSdk.iPhoneOS,
        targetVersion: targetIOSVersion,
      ),
      cCompiler: cCompiler,
    );

  final buildInput = BuildInput(buildInputBuilder.json);
  final buildOutput = BuildOutputBuilder();

  final cbuilder = CMakeBuilder.create(
    name: name,
    sourceDir: 'test/builder/testfiles/add',
    buildMode: BuildMode.release,
  );
  await cbuilder.run(
    input: buildInput,
    output: buildOutput,
    logger: logger,
  );

  final libUri = tempUri.resolve(OS.iOS.libraryFileName(name, linkMode));
  return libUri;
}
