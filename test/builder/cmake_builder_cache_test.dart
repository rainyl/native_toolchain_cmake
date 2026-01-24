@OnPlatform({'mac-os': Timeout.factor(2), 'windows': Timeout.factor(10)})
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const name = 'hello_world';
  const sourceDir = 'test/builder/testfiles/hello_world';

  test('CMakeBuilder skipGenerateIfCached', () async {
    final tempUri = await tempDirForTest();
    final tempUri2 = await tempDirForTest();

    final logMessages = <String>[];
    final logger = createCapturingLogger(logMessages);

    final buildInputBuilder = BuildInputBuilder()
      ..setupShared(
        packageName: name,
        packageRoot: tempUri,
        outputFile: tempUri.resolve('output.json'),
        outputDirectoryShared: tempUri2,
      )
      ..config.setupBuild(linkingEnabled: false)
      ..addExtension(
        CodeAssetExtension(
          targetOS: OS.current,
          macOS: OS.current == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null,
          targetArchitecture: Architecture.current,
          linkModePreference: LinkModePreference.dynamic,
          cCompiler: cCompiler,
        ),
      );

    final buildInput = BuildInput(buildInputBuilder.json);
    final buildOutput = BuildOutputBuilder();

    final builder = CMakeBuilder.create(
      name: name,
      sourceDir: Directory(sourceDir).absolute.uri,
      buildMode: BuildMode.release,
      androidArgs: const AndroidBuilderArgs(),
      appleArgs: const AppleBuilderArgs(),
    );

    // First run: Generate and build
    await builder.run(input: buildInput, output: buildOutput, logger: logger, skipGenerateIfCached: false);

    // Verify first run logs DO NOT contain the skip message
    expect(logMessages, isNot(contains(contains('CMake project is already successfully generated'))));

    // Clear logs for second run
    logMessages.clear();

    // Second run: Skip generate if cached
    await builder.run(input: buildInput, output: buildOutput, logger: logger, skipGenerateIfCached: true);

    // Verify second run logs DO contain the skip message
    expect(
      logMessages,
      contains(
        contains(
          'CMake project is already successfully generated and skipGenerateIfCached is requested, skip generating.',
        ),
      ),
    );
  });
}
