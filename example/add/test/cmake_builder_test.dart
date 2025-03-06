@OnPlatform({
  'mac-os': Timeout.factor(2),
  'windows': Timeout.factor(10),
})
import 'dart:ffi';
import 'dart:io';

import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:add/src/hook_helpers/hook_helpers.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final targetOS = OS.current;
  final macOSConfig = targetOS == OS.macOS ? MacOSCodeConfig(targetVersion: 12) : null;

  for (final buildMode in BuildMode.values) {
    // works fine
    test('CMakeBuilder-library-$buildMode', () async {
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
          targetOS: targetOS,
          macOS: macOSConfig,
          targetArchitecture: Architecture.current,
          // Ignored by executables.
          linkModePreference: LinkModePreference.dynamic,
        );

      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      await runBuild(buildInput, buildOutput, Directory("src").absolute.uri);

      final dylibUri = tempUri.resolve('install/lib/${OS.current.dylibFileName(name)}');
      expect(await File.fromUri(dylibUri).exists(), true);
      final dylib = openDynamicLibraryForTest(dylibUri.toFilePath());
      final add = dylib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('math_add');
      expect(add(1, 2), 3);
    });
  }
}
