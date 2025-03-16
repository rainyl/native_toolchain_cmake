import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/data_assets.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/utils/add_assets.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final logger = Logger('AddAssetsTest');

  group('addLibraries', () {
    test('finds and adds library files matching expected names', () async {
      // Create temporary directories as URIs.
      final baseDir = await tempDirForTest();
      final sharedDir = await tempDirForTest();

      // Create a "lib" subdirectory.
      final libDir = Directory.fromUri(baseDir.resolve('lib'));
      await libDir.create();

      // Based on the current OS, create a dummy dynamic library file for the "add" project.
      final libFileName = OS.current.dylibFileName('add'); // e.g. add.dll, libadd.so, or add.dylib.
      final libFile = File.fromUri(baseDir.resolve('lib').resolve(libFileName));
      await libFile.writeAsString('dummy library content');

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'add',
          packageRoot: baseDir,
          outputFile: baseDir.resolve('output.json'),
          outputDirectory: baseDir,
          outputDirectoryShared: sharedDir,
        )
        ..config.setupBuild(linkingEnabled: true, dryRun: false)
        ..config.setupShared(buildAssetTypes: [CodeAsset.type])
        ..config.setupCode(
          targetOS: OS.current,
          linkModePreference: LinkModePreference.dynamic,
          targetArchitecture: Architecture.current,
        );

      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      // Call addLibraries with the provided dynamic library names.
      final found = await addFoundCodeAssets(
        buildInput,
        buildOutput,
        outDir: baseDir,
        names: {'add': 'add.dart'},
        logger: logger,
      );

      // Validate that one library file was found.
      expect(found.length, equals(1));
      // The file should reside in a "lib" subdirectory.
      expect(found.first.toFilePath(), equals(libFile.absolute.path));
    });
  });
}
