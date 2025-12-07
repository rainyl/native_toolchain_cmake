// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const targets = [Architecture.arm, Architecture.arm64, Architecture.ia32, Architecture.x64];

  const objdumpFileFormat = {
    Architecture.arm: 'elf32-littlearm',
    Architecture.arm64: 'elf64-littleaarch64',
    Architecture.ia32: 'elf32-i386',
    Architecture.x64: 'elf64-x86-64',
  };

  /// From https://docs.flutter.dev/reference/supported-platforms.
  const flutterAndroidNdkVersionLowestBestEffort = 19;

  /// From https://docs.flutter.dev/reference/supported-platforms.
  const flutterAndroidNdkVersionLowestSupported = 21;

  /// From https://docs.flutter.dev/reference/supported-platforms.
  const flutterAndroidNdkVersionHighestSupported = 34;

  for (final linkMode in [DynamicLoadingBundled()]) {
    for (final target in targets) {
      for (final apiLevel in [
        flutterAndroidNdkVersionLowestBestEffort,
        flutterAndroidNdkVersionLowestSupported,
        flutterAndroidNdkVersionHighestSupported,
      ]) {
        for (final enableUserDefinedConfig in [true, false]) {
          test('CMakeBuilder $linkMode library $target minSdkVersion $apiLevel enableUserDefinedConfig $enableUserDefinedConfig', () async {
            final tempUri = await tempDirForTest();
            final libUri = await buildLib(
              tempUri,
              target,
              apiLevel,
              linkMode,
              enableUserDefinedConfig: enableUserDefinedConfig,
            );
            if (Platform.isLinux) {
              final machine = await readelfMachine(libUri.path);
              expect(machine, contains(readElfMachine[target]));
            } else if (Platform.isMacOS) {
              final result = await runProcess(
                executable: Uri.file('objdump'),
                arguments: ['-T', libUri.path],
                logger: logger,
              );
              expect(result.exitCode, 0);
              final machine = result.stdout.split('\n').firstWhere((e) => e.contains('file format'));
              expect(machine, contains(objdumpFileFormat[target]));
            }
            // TODO: failed
            // if (linkMode == DynamicLoadingBundled()) {
            //   await expectPageSize(libUri, 16 * 1024);
            // }
          });
        }
      }
    }
  }

  // test('page size override', () async {
  //   const target = Architecture.arm64;
  //   final linkMode = DynamicLoadingBundled();
  //   const apiLevel1 = flutterAndroidNdkVersionLowestSupported;
  //   final tempUri = await tempDirForTest();
  //   final outUri = tempUri.resolve('out1/');
  //   await Directory.fromUri(outUri).create();
  //   const pageSize = 4 * 1024;
  //   final libUri = await buildLib(
  //     outUri,
  //     target,
  //     apiLevel1,
  //     linkMode,
  //   );
  //   if (Platform.isMacOS || Platform.isLinux) {
  //     final address = await textSectionAddress(libUri);
  //     expect(address, greaterThanOrEqualTo(pageSize));
  //     expect(address, isNot(greaterThanOrEqualTo(pageSize * 4)));
  //   }
  // });
}

Future<Uri> buildLib(
  Uri tempUri,
  Architecture targetArchitecture,
  int androidNdkApi,
  LinkMode linkMode, {
  bool enableUserDefinedConfig = false,
}) async {
  const name = 'add';

  const userDefinedConfig = {"envFile": ".env"};
  if (enableUserDefinedConfig) {
    // cmakeVersion ninjaVersion ndkVersion envFile
    // TODO: add more user configs.
    final envFilePath = tempUri.resolve(userDefinedConfig["envFile"] as String).toFilePath();
    final envFile = File(envFilePath);
    await envFile.writeAsString(r'ANDROID_HOME=$HOME/Android/Sdk');
  }

  final tempUriShared = tempUri.resolve('shared/');
  await Directory.fromUri(tempUriShared).create();
  final buildInputBuilder = BuildInputBuilder()
    ..setupShared(
      packageName: name,
      packageRoot: tempUri,
      outputFile: tempUri.resolve('output.json'),
      outputDirectoryShared: tempUriShared,
      userDefines: enableUserDefinedConfig
          ? PackageUserDefines(
              workspacePubspec: PackageUserDefinesSource(defines: userDefinedConfig, basePath: tempUri),
            )
          : null,
    )
    ..config.setupBuild(linkingEnabled: false)
    ..addExtension(
      CodeAssetExtension(
        targetArchitecture: targetArchitecture,
        targetOS: OS.android,
        cCompiler: cCompiler,
        android: AndroidCodeConfig(targetNdkApi: androidNdkApi),
        linkModePreference: linkMode == DynamicLoadingBundled()
            ? LinkModePreference.dynamic
            : LinkModePreference.static,
      ),
    );

  final buildInput = BuildInput(buildInputBuilder.json);
  final buildOutput = BuildOutputBuilder();

  final builder = CMakeBuilder.create(
    name: name,
    sourceDir: Directory('test/builder/testfiles/add').absolute.uri,
    buildMode: BuildMode.release,
    generator: Generator.ninja,
    androidArgs: AndroidBuilderArgs(androidAPI: androidNdkApi),
  );
  await builder.run(input: buildInput, output: buildOutput, logger: logger);

  final libUri = buildInput.outputDirectory.resolve(OS.android.libraryFileName(name, linkMode));
  return libUri;
}
