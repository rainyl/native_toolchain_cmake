import 'dart:io';
import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'package:native_assets_cli/data_assets.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/utils/find_assets.dart';

void main() {
  final logger = Logger('FindAssetsTest');

  group('findDirectories', () {
    test('finds files recursively and computes relative paths', () async {
      // Create temporary directories for packageRoot, outputFile, and outputDirectoryShared.
      final baseDir = await Directory.systemTemp.createTemp('find_directories_test_');
      final sharedDir = await Directory.systemTemp.createTemp('shared_');

      // Create a nested structure:
      // baseDir/
      //   asset1.txt
      //   subdir/asset2.txt
      final file1 = File('${baseDir.path}${Platform.pathSeparator}asset1.txt');
      await file1.writeAsString('Content 1');
      final subdir = Directory('${baseDir.path}${Platform.pathSeparator}subdir');
      await subdir.create();
      final file2 = File('${subdir.path}${Platform.pathSeparator}asset2.txt');
      await file2.writeAsString('Content 2');

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'test_package',
          packageRoot: baseDir.uri,
          outputFile: baseDir.uri.resolve('output.json'),
          outputDirectory: baseDir.uri,
          outputDirectoryShared: sharedDir.uri,
        )
        ..config.setupBuild(linkingEnabled: false, dryRun: true)
        ..config.setupShared(buildAssetTypes: [DataAsset.type]);

      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      final found = await findDirectories(
        buildInput,
        buildOutput,
        [baseDir.uri],
        packageName: 'test_package',
        logger: logger,
      );

      // Verify that two files are found.
      expect(found.length, equals(2));

      // Using the outputDirectory from buildInput (which is a URI), compute the expected relative paths.
      final basePath = buildInput.outputDirectory.toFilePath(windows: Platform.isWindows);
      final expectedNames = [
        file1.uri.toFilePath(windows: Platform.isWindows).substring(basePath.length + 1),
        file2.uri.toFilePath(windows: Platform.isWindows).substring(basePath.length + 1),
      ];

      // Verify that each returned file URI, when resolved against the base, yields one of the expected names.
      final foundNames = found.map((uri) {
        final fPath = uri.toFilePath(windows: Platform.isWindows);
        return fPath.substring(basePath.length + 1);
      }).toList();

      expect(foundNames, containsAllInOrder(expectedNames));

      // Cleanup.
      await baseDir.delete(recursive: true);
      await sharedDir.delete(recursive: true);
    });
  });

  group('findAssets', () {
    test('finds only files matching provided asset names', () async {
      // Create temporary directories as URIs.
      final baseDir = await Directory.systemTemp.createTemp('find_assets_test_');
      final sharedDir = await Directory.systemTemp.createTemp('shared_');

      // Create files:
      // baseDir/
      //   lib.js
      //   data.json
      //   ignore.txt
      final fileJs = File('${baseDir.path}${Platform.pathSeparator}lib.js');
      await fileJs.writeAsString('JS content');
      final fileJson = File('${baseDir.path}${Platform.pathSeparator}data.json');
      await fileJson.writeAsString('JSON content');
      final fileIgnore = File('${baseDir.path}${Platform.pathSeparator}ignore.txt');
      await fileIgnore.writeAsString('Ignore me');

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'test_package',
          packageRoot: baseDir.uri,
          outputFile: baseDir.uri.resolve('output.json'),
          outputDirectory: baseDir.uri,
          outputDirectoryShared: sharedDir.uri,
        )
        ..config.setupBuild(linkingEnabled: false, dryRun: true)
        ..config.setupShared(buildAssetTypes: [DataAsset.type]);
      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      final found = await findAssets(
        buildInput,
        buildOutput,
        baseDir.uri,
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

      // Cleanup.
      await baseDir.delete(recursive: true);
      await sharedDir.delete(recursive: true);
    });
  });

  group('findLibraries', () {
    test('finds library files matching expected names', () async {
      // Create temporary directories as URIs.
      final baseDir = await Directory.systemTemp.createTemp('find_libraries_test_');
      final sharedDir = await Directory.systemTemp.createTemp('shared_');

      // Create a "lib" subdirectory.
      final libDirPath = '${baseDir.path}${Platform.pathSeparator}lib';
      final libDir = Directory(libDirPath);
      await libDir.create();

      // Based on the current OS, create a dummy dynamic library file for the "add" project.
      final libFileName = OS.current.dylibFileName('add'); // e.g. add.dll, libadd.so, or add.dylib.
      final libFile = File('$libDirPath${Platform.pathSeparator}$libFileName');
      await libFile.writeAsString('dummy library content');

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'add',
          packageRoot: baseDir.uri,
          outputFile: baseDir.uri.resolve('output.json'),
          outputDirectory: baseDir.uri,
          outputDirectoryShared: sharedDir.uri,
        )
        ..config.setupBuild(linkingEnabled: true, dryRun: true)
        ..config.setupShared(buildAssetTypes: [CodeAsset.type])
        ..config.setupCode(
          targetOS: OS.current,
          linkModePreference: LinkModePreference.dynamic,
          targetArchitecture: Architecture.current,
        );

      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      // Call findLibraries with the provided dynamic library names.
      final found = await findLibraries(
        buildInput,
        buildOutput,
        baseDir.uri,
        packageName: 'add',
        dynLibNames: ['add'],
        staticLibNames: [],
        logger: logger,
      );

      // Validate that one library file was found.
      expect(found.length, equals(1));
      final foundLibUri = found.first;
      // The file should reside in a "lib" subdirectory.
      final expectedLibPath = '$libDirPath${Platform.pathSeparator}$libFileName';
      expect(foundLibUri.toFilePath(windows: Platform.isWindows), equals(expectedLibPath));

      // Cleanup.
      await baseDir.delete(recursive: true);
      await sharedDir.delete(recursive: true);
    });
  });
}
