import 'dart:io';
import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/builder/builder.dart';
import 'package:native_assets_cli/code_assets_builder.dart';

void main() {
  group('CMakeBuilder.fromGit', () {
    late Directory tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cmake_builder_git_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should create external directory for git clone', () {
      final sourceDir = Uri.directory(tempDir.path + Platform.pathSeparator);
      // Instantiate builder with a non-empty gitSubDir so that the external directory gets created.
      final builder = CMakeBuilder.fromGit(
        name: 'add',
        gitUrl: 'https://github.com/rainyl/native_toolchain_cmake.git',
        sourceDir: sourceDir,
        gitSubDir: 'example/add/src',
      );

      // The builder constructor creates a directory at sourceDir/external/<name>
      final extDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}external${Platform.pathSeparator}add');
      expect(extDir.existsSync(), isTrue,
          reason: 'External directory should be created.');
    });
  });

  group('CMakeBuilder.run', () {
    late Directory tempDir;
    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('cmake_builder_git_run_test');
    });
    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should create output directory when buildLocal is set', () async {
      final sourceDir = Uri.directory(tempDir.path + Platform.pathSeparator);
      // Create builder with buildLocal true.
      final builder = CMakeBuilder.fromGit(
        name: 'add',
        gitUrl: 'https://github.com/rainyl/native_toolchain_cmake.git',
        sourceDir: sourceDir,
        gitSubDir: '',
        buildLocal: true,
      );

      // Use real build input/output objects.
      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'add',
          packageRoot: sourceDir,
          outputFile: sourceDir.resolve('output.json'),
          outputDirectory: sourceDir,
          outputDirectoryShared: sourceDir,
        )
        ..config.setupBuild(
          linkingEnabled: false,
          dryRun: false,
        )
        ..config.setupShared(
          buildAssetTypes: [CodeAsset.type],
        )
        ..config.setupCode(
          targetOS: OS.current,
          targetArchitecture: Architecture.current,
          linkModePreference: LinkModePreference.dynamic,
        );
      final input = BuildInput(buildInputBuilder.json);
      final output = BuildOutputBuilder();

      // Run the builder.
      try {
        await builder.run(input: input, output: output, logger: Logger('Test'));
      } catch (_) {
        // Ignore errors from running external tools.
      }

      // The builder.run method should set outDir under sourceDir/build/<os>/<arch>
      final osName = input.config.code.targetOS.name.toLowerCase();
      final archName = input.config.code.targetArchitecture.name.toLowerCase();
      final buildDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}build${Platform.pathSeparator}$osName${Platform.pathSeparator}$archName');
      expect(
        buildDir.existsSync(),
        isTrue,
        reason: 'Build directory should be created when buildLocal is true.',
      );
    });
  });
}
