@OnPlatform({
  'mac-os': Timeout.factor(2),
  'windows': Timeout.factor(10),
})
import 'dart:ffi';
import 'dart:io';

import 'package:change_case/change_case.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const sourceDirs = [
  'test/builder/testfiles/hello_world',
  'test/builder/testfiles/hello_world_cpp',
];

void main() {
  final targetOS = OS.current;
  final macOSConfig = targetOS == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null;

  // executable
  for (final buildMode in BuildMode.values) {
    for (final sourceDir in sourceDirs) {
      final name = sourceDir.split("/").last;
      test('CMakeBuilder-executable-$name-$buildMode', () async {
        final tempUri = await tempDirForTest();
        final tempUri2 = await tempDirForTest();

        final logMessages = <String>[];
        final logger = createCapturingLogger(logMessages);

        final buildInputBuilder = BuildInputBuilder()
          ..setupShared(
            packageName: name,
            packageRoot: tempUri,
            outputFile: tempUri.resolve('output.json'),
            outputDirectory: tempUri,
            outputDirectoryShared: tempUri2,
          )
          ..config.setupBuild(linkingEnabled: false)
          ..config.setupShared(buildAssetTypes: [CodeAsset.type])
          ..config.setupCode(
            targetOS: targetOS,
            macOS: macOSConfig,
            targetArchitecture: Architecture.current,
            // Ignored by executables.
            linkModePreference: LinkModePreference.dynamic,
            cCompiler: cCompiler,
          );

        final buildInput = BuildInput(buildInputBuilder.json);
        final buildOutput = BuildOutputBuilder();

        final builder = CMakeBuilder.create(
          name: name,
          sourceDir: Directory(sourceDir).absolute.uri,
          buildMode: buildMode,
          androidArgs: const AndroidBuilderArgs(),
          appleArgs: const AppleBuilderArgs(),
        );
        await builder.run(input: buildInput, output: buildOutput, logger: logger);

        final executableUri = switch (targetOS) {
          OS.macOS => tempUri.resolve('$name.app/Contents/MacOS/${OS.current.executableFileName(name)}'),
          OS.windows => tempUri.resolve('${buildMode.name.toCapitalCase()}/$name.exe'),
          _ => tempUri.resolve(OS.current.executableFileName(name)),
        };
        expect(await File.fromUri(executableUri).exists(), true);
        final result = await runProcess(
          executable: executableUri,
          logger: logger,
        );
        expect(result.exitCode, 0);
        if (buildMode == BuildMode.debug) {
          expect(result.stdout.trim(), startsWith('Running in debug mode.'));
        }
        expect(result.stdout.trim(), endsWith('Hello world.'));
      });
    }

    test('CMakeBuilder-library-$buildMode', () async {
      final tempUri = await tempDirForTest();
      final tempUri2 = await tempDirForTest();

      final logMessages = <String>[];
      final logger = createCapturingLogger(logMessages);
      const name = 'add';

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: name,
          packageRoot: tempUri,
          outputFile: tempUri.resolve('output.json'),
          outputDirectory: tempUri,
          outputDirectoryShared: tempUri2,
        )
        ..config.setupBuild(linkingEnabled: false)
        ..config.setupShared(buildAssetTypes: [CodeAsset.type])
        ..config.setupCode(
          targetOS: targetOS,
          macOS: macOSConfig,
          targetArchitecture: Architecture.current,
          // Ignored by executables.
          linkModePreference: LinkModePreference.dynamic,
          cCompiler: cCompiler,
        );

      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      final builder = CMakeBuilder.create(
        name: name,
        sourceDir: Directory('test/builder/testfiles/add').absolute.uri,
        buildMode: buildMode,
        defines: {
          'CMAKE_INSTALL_PREFIX': buildInput.outputDirectory.resolve('install').toFilePath(),
        },
        targets: ['install'],
        androidArgs: const AndroidBuilderArgs(),
        appleArgs: const AppleBuilderArgs(),
      );
      await builder.run(input: buildInput, output: buildOutput, logger: logger);

      final dylibUri = tempUri.resolve('install/lib/${OS.current.dylibFileName(name)}');
      expect(await File.fromUri(dylibUri).exists(), true);
      final dylib = openDynamicLibraryForTest(dylibUri.toFilePath());
      final add = dylib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('add');
      expect(add(1, 2), 3);
    });

    test('CMakeBuilder define $buildMode', () => testDefines(buildMode: buildMode));
  }
}

Future<void> testDefines({BuildMode buildMode = BuildMode.debug}) async {
  final tempUri = await tempDirForTest();
  final tempUri2 = await tempDirForTest();
  const name = 'defines';

  final targetOS = OS.current;
  final buildInputBuilder = BuildInputBuilder()
    ..setupShared(
      packageName: name,
      packageRoot: tempUri,
      outputFile: tempUri.resolve('output.json'),
      outputDirectory: tempUri,
      outputDirectoryShared: tempUri2,
    )
    ..config.setupBuild(linkingEnabled: false)
    ..config.setupShared(buildAssetTypes: [CodeAsset.type])
    ..config.setupCode(
      targetOS: targetOS,
      macOS: targetOS == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null,
      targetArchitecture: Architecture.current,
      // Ignored by executables.
      linkModePreference: LinkModePreference.dynamic,
      cCompiler: cCompiler,
    );

  final buildInput = BuildInput(buildInputBuilder.json);
  final buildOutput = BuildOutputBuilder();

  final builder = CMakeBuilder.create(
    name: name,
    sourceDir: Directory('test/builder/testfiles/defines').absolute.uri,
    buildMode: buildMode,
    androidArgs: const AndroidBuilderArgs(),
    appleArgs: const AppleBuilderArgs(),
  );
  await builder.run(
    input: buildInput,
    output: buildOutput,
    logger: logger,
  );

  final executableUri = switch (targetOS) {
    OS.macOS => tempUri.resolve('$name.app/Contents/MacOS/${OS.current.executableFileName(name)}'),
    OS.windows => tempUri.resolve('${buildMode.name.toCapitalCase()}/$name.exe'),
    _ => tempUri.resolve(OS.current.executableFileName(name)),
  };
  expect(await File.fromUri(executableUri).exists(), true);
  final result = await runProcess(
    executable: executableUri,
    logger: logger,
  );
  expect(result.exitCode, 0);

  if (buildMode == BuildMode.release) {
    expect(
      result.stdout,
      contains('Macro NDEBUG is defined: 1'),
    );
  } else {
    expect(
      result.stdout,
      contains('Macro NDEBUG is undefined.'),
    );
    expect(
      result.stdout,
      contains('Macro DEBUG is defined: 1'),
    );
  }

  expect(
    result.stdout,
    contains('Macro FOO is defined: BAR'),
  );
}
