import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/data_assets.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/utils/add_assets.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final logger = Logger('AddAssetsTest');

  group('AddDirectories', () {
    test('finds and adds files recursively and computes relative paths', () async {
      // Create temporary directories for packageRoot, outputFile, and outputDirectoryShared.
      final baseDir = await tempDirForTest();
      final sharedDir = await tempDirForTest();

      // Create a nested structure:
      // baseDir/
      //   asset1.txt
      //   subdir/asset2.txt
      final file1 = File.fromUri(baseDir.resolve('asset1.txt'));
      await file1.writeAsString('Content 1');
      final subdir = Directory.fromUri(baseDir.resolve('subdir'));
      await subdir.create();
      final file2 = File.fromUri(subdir.uri.resolve('asset2.txt'));
      await file2.writeAsString('Content 2');

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'test_package',
          packageRoot: baseDir,
          outputFile: baseDir.resolve('output.json'),
          outputDirectory: baseDir,
          outputDirectoryShared: sharedDir,
        )
        ..config.setupBuild(linkingEnabled: false, dryRun: true)
        ..config.setupShared(buildAssetTypes: [DataAsset.type]);

      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      final found = await addDirectories(
        buildInput,
        buildOutput,
        [baseDir],
        packageName: 'test_package',
        logger: logger,
      );

      // Verify that two files are found.
      expect(found.length, equals(2));

      // Using the outputDirectory from buildInput (which is a URI), compute the expected relative paths.
      final basePath = buildInput.outputDirectory.toFilePath();
      final expectedNames = [
        file1.uri.toFilePath().substring(basePath.length + 1),
        file2.uri.toFilePath().substring(basePath.length + 1),
      ];

      // Verify that each returned file URI, when resolved against the base, yields one of the expected names.
      final foundNames = found.map((uri) {
        final fPath = uri.toFilePath();
        return fPath.substring(basePath.length + 1);
      }).toList();

      expect(foundNames, containsAll(expectedNames));
    });
  });

  group('addDataAssets', () {
    test('finds and adds only files matching provided asset names', () async {
      // Create temporary directories as URIs.
      final baseDir = await tempDirForTest();
      final sharedDir = await tempDirForTest();

      // Create files:
      // baseDir/
      //   lib.js
      //   data.json
      //   ignore.txt
      final fileJs = File.fromUri(baseDir.resolve('lib.js'));
      await fileJs.writeAsString('JS content');
      final fileJson = File.fromUri(baseDir.resolve('data.json'));
      await fileJson.writeAsString('JSON content');
      final fileIgnore = File.fromUri(baseDir.resolve('ignore.txt'));
      await fileIgnore.writeAsString('Ignore me');

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'test_package',
          packageRoot: baseDir,
          outputFile: baseDir.resolve('output.json'),
          outputDirectory: baseDir,
          outputDirectoryShared: sharedDir,
        )
        ..config.setupBuild(linkingEnabled: false, dryRun: true)
        ..config.setupShared(buildAssetTypes: [DataAsset.type]);
      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      final found = await addDataAssets(
        buildInput,
        buildOutput,
        outDir: baseDir,
        packageName: 'test_package',
        assetNames: ['lib.js', 'data.json'],
        logger: logger,
      );

      // Verify that only the matching files are found.
      expect(found.length, equals(2));

      // Check that the found URIs correspond to the expected files.
      final foundFiles = found.map((uri) => uri.toFilePath(windows: Platform.isWindows));
      expect(foundFiles, contains(fileJs.absolute.path));
      expect(foundFiles, contains(fileJson.absolute.path));
      expect(foundFiles, isNot(contains(fileIgnore.absolute.path)));
    });
  });

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
      final found = await addCodeAssets(
        buildInput,
        buildOutput,
        outDir: baseDir,
        packageName: 'add',
        patternMap: {
          RegExp(r'(lib)add\.(so|dylib|dll)'): 'add',
        },
        logger: logger,
      );

      // Validate that one library file was found.
      expect(found.length, equals(1));
      // The file should reside in a "lib" subdirectory.
      expect(found.first.toFilePath(), equals(libFile.absolute.path));
    });
  });
}
