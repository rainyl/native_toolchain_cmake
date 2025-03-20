import 'dart:ffi';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/builder/builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final targetOS = OS.current;
  final macOSConfig = targetOS == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null;

  group('CMakeBuilder.fromGit', () {
    for (final subdir in ['', 'example/add/src']) {
      test('create external dir with subdir=$subdir', () async {
        final tempDir = await tempDirForTest();
        // Instantiate builder with a non-empty gitSubDir so that the external directory gets created.
        final builder = CMakeBuilder.fromGit(
          name: 'add',
          gitUrl: 'https://github.com/rainyl/native_toolchain_cmake.git',
          sourceDir: tempDir,
          gitSubDir: subdir,
          logger: Logger('')
            ..level = Level.ALL
            ..onRecord.listen((record) => stderr.writeln(record)),
        );

        // The builder constructor creates a directory at sourceDir/external/<name>
        expect(builder.cmakeListsDir, tempDir.resolve('external/add/').resolve(subdir).normalizePath());
        final extDir = Directory.fromUri(tempDir.resolve('external/add/').resolve(subdir).normalizePath());
        expect(extDir.existsSync(), isTrue, reason: 'External directory should be created.');
        expect(extDir.listSync(), isNotEmpty);
      });
    }
  });

  group('CMakeBuilder.run', () {
    for (final buildLocal in [true, false]) {
      test('buildLocal=$buildLocal', () async {
        final tempDir = await tempDirForTest();
        final logMessages = <String>[];
        final logger = createCapturingLogger(logMessages);

        // Create builder with buildLocal true.
        final builder = CMakeBuilder.fromGit(
          name: 'add',
          gitUrl: 'https://github.com/rainyl/native_toolchain_cmake.git',
          sourceDir: tempDir,
          gitSubDir: 'example/add/src',
          buildLocal: buildLocal,
          logger: logger,
          defines: {
            'CMAKE_INSTALL_PREFIX': 'install',
          },
          targets: ['install'],
        );

        // Use real build input/output objects.
        final buildInputBuilder = BuildInputBuilder()
          ..setupShared(
            packageName: 'add',
            packageRoot: tempDir,
            outputFile: tempDir.resolve('output.json'),
            outputDirectory: tempDir,
            outputDirectoryShared: tempDir,
          )
          ..config.setupBuild(
            linkingEnabled: false,
            dryRun: false,
          )
          ..config.setupShared(
            buildAssetTypes: [CodeAsset.type],
          )
          ..config.setupCode(
            targetOS: targetOS,
            macOS: macOSConfig,
            targetArchitecture: Architecture.current,
            linkModePreference: LinkModePreference.dynamic,
          );
        final input = BuildInput(buildInputBuilder.json);
        final output = BuildOutputBuilder();

        // Run the builder.
        await builder.run(input: input, output: output);

        // The builder.run method should set outDir under sourceDir/build/<os>/<arch>
        final osName = input.config.code.targetOS.name.toLowerCase();
        final archName = input.config.code.targetArchitecture.name.toLowerCase();
        final buildDir = buildLocal
            ? Directory.fromUri(
                tempDir.resolve('build/').resolve("$osName/").resolve(archName).normalizePath())
            : Directory.fromUri(input.outputDirectory);
        expect(
          buildDir.existsSync(),
          isTrue,
          reason: 'Build directory should be created when buildLocal is true.',
        );

        // check built libs
        final dylibUri = buildDir.uri.resolve('install/lib/${OS.current.dylibFileName('add')}');
        expect(File.fromUri(dylibUri).existsSync(), true);
        final dylib = openDynamicLibraryForTest(dylibUri.toFilePath());
        final add = dylib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('math_add');
        expect(add(1, 2), 3);
      });
    }
  });
}
