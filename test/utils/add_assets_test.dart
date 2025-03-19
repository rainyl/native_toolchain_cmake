import 'dart:io';

import 'package:logging/logging.dart';
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

      {
        final buildOutput = BuildOutputBuilder();
        // Call addLibraries with the provided dynamic library names.
        final added = await buildOutput.findAndAddCodeAssets(
          buildInput,
          outDir: baseDir,
          names: {'add': 'add.dart'},
          logger: logger,
        );

        // Validate that one library file was added.
        expect(added.length, equals(1));
        // The file should reside in a "lib" subdirectory.
        expect(added.first.file?.toFilePath(), equals(libFile.absolute.path));
      }

      {
        final buildOutput = BuildOutputBuilder();
        // Call addLibraries with the provided dynamic library names.
        final added = await buildOutput.findAndAddCodeAssets(
          buildInput,
          outDir: baseDir,
          names: {r'(lib)?add\.(dll|so|dylib)': 'add.dart'},
          logger: logger,
          regExp: true,
        );

        // Validate that one library file was added.
        expect(added.length, equals(1));
        // The file should reside in a "lib" subdirectory.
        expect(added.first.file?.toFilePath(), equals(libFile.absolute.path));
      }
    });
  });

  test('does not add duplicate asset for the same library file', () async {
    // Create temporary directories as URIs.
    final baseDir = await tempDirForTest();
    final sharedDir = await tempDirForTest();

    // Create a "lib" subdirectory.
    final libDir = Directory.fromUri(baseDir.resolve('lib'));
    await libDir.create();

    // Based on the current OS, create a dummy dynamic library file for the "add" project.
    final libFileName = OS.current.dylibFileName('add'); // e.g. add.dll, libadd.so, or add.dylib.
    final libFile = File.fromUri(libDir.uri.resolve(libFileName));
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

    // First call should add the asset.
    final addedFirst = await buildOutput.findAndAddCodeAssets(
      buildInput,
      outDir: baseDir,
      names: {'add': 'add.dart'},
      logger: logger,
    );
    expect(addedFirst.length, equals(1));

    // Second call should not add the asset again since it's already added.
    final addedSecond = await buildOutput.findAndAddCodeAssets(
      buildInput,
      outDir: baseDir,
      names: {'add': 'add.dart'},
      logger: logger,
    );
    // No assets should be added.
    expect(addedSecond.length, equals(0));
  });

  test('does not add duplicate asset when libraries exist in nested directories', () async {
    // Create temporary directories as URIs.
    final baseDir = await tempDirForTest();
    final sharedDir = await tempDirForTest();

    // Create a top-level "lib" subdirectory.
    final libDir = Directory.fromUri(baseDir.resolve('lib'));
    await libDir.create();

    // Create a nested subdirectory under "lib".
    final nestedDir = Directory.fromUri(libDir.uri.resolve('nested'));
    await nestedDir.create();

    // Determine the dynamic library file name.
    final libFileName = OS.current.dylibFileName('add');

    // Create a library file in the top-level "lib" directory.
    final topLibFile = File.fromUri(libDir.uri.resolve(libFileName));
    await topLibFile.writeAsString('top level library content');

    // Create another library file with the same name in the nested directory.
    final nestedLibFile = File.fromUri(nestedDir.uri.resolve(libFileName));
    await nestedLibFile.writeAsString('nested library content');

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

    // The call should find matching library files but add only one asset.
    final added = await buildOutput.findAndAddCodeAssets(
      buildInput,
      outDir: baseDir,
      names: {'add': 'add.dart'},
      logger: logger,
    );

    expect(added.length, equals(1));
  });
}
