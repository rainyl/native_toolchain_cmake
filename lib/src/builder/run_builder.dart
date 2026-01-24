// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
//
// This file is adapted from https://github.com/dart-lang/native/tree/main/pkgs/native_toolchain_c
// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math';

import 'package:change_case/change_case.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import '../native_toolchain/android_ndk.dart';
import '../native_toolchain/cmake.dart';
import '../native_toolchain/ninja.dart';
import '../native_toolchain/xcode.dart';
import '../tool/tool_instance.dart';
import '../utils/package_config_parser.dart';
import '../utils/run_process.dart';
import 'build_mode.dart';
import 'builder_args.dart';
import 'generator.dart';
import 'log_level.dart';
import 'user_config.dart';

class RunCMakeBuilder {
  final HookInput input;
  final CodeConfig codeConfig;
  final Logger? logger;
  final Uri sourceDir;
  final Uri outDir;

  /// -D
  final Map<String, String?> defines;

  /// -DCMAKE_BUILD_TYPE
  final BuildMode buildMode;

  /// -G
  Generator generator;

  /// -T
  final String? toolset;

  final List<String>? targets;

  // ios.toolchain.cmake
  // https://github.com/leetal/ios-cmake?tab=readme-ov-file#exposed-variables
  final AppleBuilderArgs appleArgs;

  // android ndk
  final AndroidBuilderArgs androidArgs;

  // user defined configs
  final UserConfig userConfig;

  /// log level of CMake
  final LogLevel logLevel;

  /// save the last generate status of native_toolchain_cmake
  final String lastGenStatusFile;

  RunCMakeBuilder({
    required this.input,
    required this.codeConfig,
    required this.sourceDir,
    this.logger,
    this.defines = const {},
    this.generator = Generator.defaultGenerator,
    this.toolset,
    this.buildMode = BuildMode.release,
    this.targets,
    this.androidArgs = const AndroidBuilderArgs(),
    this.appleArgs = const AppleBuilderArgs(),
    this.logLevel = LogLevel.STATUS,
    this.lastGenStatusFile = 'ntc_last_generate_status.txt',
    Uri? outputDir,
    UserConfig? userConfig,
  }) : outDir = outputDir ?? input.outputDirectory,
       userConfig = userConfig ?? UserConfig(targetOS: codeConfig.targetOS);

  Future<Uri> cmakePath() async {
    final cmakeTools = await cmake.defaultResolver?.resolve(logger: logger, userConfig: userConfig);
    final path = cmakeTools?.first.uri;
    assert(path != null);
    return Future.value(path);
  }

  Future<Uri> ninjaPath() async {
    final ninjaTools = await ninja.defaultResolver?.resolve(logger: logger, userConfig: userConfig);
    final path = ninjaTools?.first.uri;
    assert(path != null);
    return Future.value(path);
  }

  Future<Uri> currentPackageRoot() async => Uri.directory(await getPackagePath("native_toolchain_cmake"));

  Future<Uri> iosToolchainCmake() async => (await currentPackageRoot()).resolve('cmake/ios.toolchain.cmake');

  Future<Uri> androidToolchainCmake() async {
    final tool = await androidNdk.defaultResolver?.resolve(logger: logger, userConfig: userConfig);
    final toolUri = tool?.first.uri.resolve('build/cmake/android.toolchain.cmake');
    assert(toolUri != null);
    return Future.value(toolUri);
  }

  Future<Uri> linuxToolchainCmake() async => switch (codeConfig.targetArchitecture) {
    Architecture.x64 => (await currentPackageRoot()).resolve('cmake/x86_64-linux-gnu.toolchain.cmake'),
    Architecture.arm64 => (await currentPackageRoot()).resolve('cmake/aarch64-linux-gnu.toolchain.cmake'),
    Architecture.riscv64 => (await currentPackageRoot()).resolve('cmake/riscv64-linux-gnu.toolchain.cmake'),
    _ => throw UnimplementedError('Unsupported architecture: ${codeConfig.targetArchitecture} for Linux'),
  };

  Future<Uri> iosSdk(IOSSdk iosSdk, {required Logger? logger}) async {
    if (iosSdk == IOSSdk.iPhoneOS) {
      return (await iPhoneOSSdk.defaultResolver!.resolve(
        logger: logger,
        userConfig: userConfig,
      )).where((i) => i.tool == iPhoneOSSdk).first.uri;
    }
    assert(iosSdk == IOSSdk.iPhoneSimulator);
    return (await iPhoneSimulatorSdk.defaultResolver!.resolve(
      logger: logger,
      userConfig: userConfig,
    )).where((i) => i.tool == iPhoneSimulatorSdk).first.uri;
  }

  Future<Uri> macosSdk({required Logger? logger}) async => (await macosxSdk.defaultResolver!.resolve(
    logger: logger,
    userConfig: userConfig,
  )).where((i) => i.tool == macosxSdk).first.uri;

  Uri androidSysroot(ToolInstance compiler) => compiler.uri.resolve('../sysroot/');

  /// Run CMake to generate and build the project.
  ///
  /// - [environment] additional environment variables to pass to CMake.
  /// - [skipGenerateIfCached] whether to skip generating the CMake project.
  Future<void> run({Map<String, String>? environment, bool skipGenerateIfCached = false}) async {
    bool skipGenerate = false;
    if (skipGenerateIfCached) {
      final cmakeCacheExists = await File.fromUri(outDir.resolve('CMakeCache.txt')).exists();
      final lastGenExitCode = await getLastGenExitCode();
      if (cmakeCacheExists && lastGenExitCode == 0) {
        logger?.warning(
          'CMake project is already successfully generated '
          'and skipGenerateIfCached is requested, skip generating.',
        );
        skipGenerate = true;
      }
    }
    if (!skipGenerate) {
      final result = await _generate(environment: environment);
      if (result.exitCode != 0) {
        throw Exception('Failed to generate CMake project: ${result.stderr}');
      }
    }

    final result1 = await _build(environment: environment);
    if (result1.exitCode != 0) {
      throw Exception('Failed to build CMake project: ${result1.stderr}');
    }
  }

  Future<RunProcessResult> _generate({Map<String, String>? environment}) async {
    final defs = switch (codeConfig.targetOS) {
      OS.windows => await _generateWindowsDefines(),
      OS.linux => await _generateLinuxDefines(),
      OS.macOS => await _generateMacosDefines(),
      OS.iOS => await _generateIOSDefines(),
      OS.android => await _generateAndroidDefines(),
      _ => throw UnimplementedError('Unsupported OS: ${codeConfig.targetOS}'),
    };

    final _defines = <String>[
      '-DCMAKE_BUILD_TYPE=${buildMode.name.toCapitalCase()}',
      if (buildMode == BuildMode.debug) '-DCMAKE_C_FLAGS_DEBUG=-DDEBUG',
      if (buildMode == BuildMode.debug) '-DCMAKE_CXX_FLAGS_DEBUG=-DDEBUG',
      ...defs,
    ];
    defines.forEach((k, v) => _defines.add('-D$k=${v ?? "1"}'));

    if (generator == Generator.ninja) {
      final ninjaBinUri = await ninjaPath();
      final ninjaBinDir = File.fromUri(ninjaBinUri).parent.path;
      _defines.add('-DCMAKE_PROGRAM_PATH=$ninjaBinDir');
    }
    final _generator = generator.toArgs();

    final results = await runProcess(
      executable: await cmakePath(),
      arguments: [
        '--log-level=${logLevel.name}',
        '-S',
        sourceDir.normalizePath().toFilePath(),
        '-B',
        outDir.normalizePath().toFilePath(),
        if (toolset != null) '-T',
        if (toolset != null) toolset!,
        ..._generator,
        ..._defines,
      ],
      workingDirectory: outDir,
      logger: logger,
      captureOutput: true,
      throwOnUnexpectedExitCode: false,
      environment: environment,
    );

    // save the last generate status
    final msg =
        "command: ${results.command}\n"
        "exitCode: ${results.exitCode}\n"
    // "stdout: ${results.stdout}\n"
    // "stderr: ${results.stderr}\n"
    ;
    await File.fromUri(outDir.resolve(lastGenStatusFile)).writeAsString(msg);

    return results;
  }

  Future<RunProcessResult> _build({Map<String, String>? environment}) async {
    return runProcess(
      executable: await cmakePath(),
      arguments: [
        '--build',
        outDir.normalizePath().toFilePath(),
        '--config',
        buildMode.name.toCapitalCase(),
        if (targets?.isNotEmpty ?? false) '--target',
        if (targets?.isNotEmpty ?? false) ...targets!,
      ],
      logger: logger,
      workingDirectory: outDir,
      captureOutput: true,
      throwOnUnexpectedExitCode: false,
      environment: environment,
    );
  }

  Future<List<String>> _generateMacosDefines() async {
    if (codeConfig.targetOS != OS.macOS) {
      return [];
    }
    final defs = <String>[];
    final toolchain = await iosToolchainCmake();
    defs.add('-DCMAKE_TOOLCHAIN_FILE=${toolchain.normalizePath().toFilePath()}');
    final platform = macosPlatforms[codeConfig.targetArchitecture];
    assert(platform != null, 'Unsupported macOS architecture: ${codeConfig.targetArchitecture}');
    defs.add('-DPLATFORM=$platform');
    defs.add('-DDEPLOYMENT_TARGET=${codeConfig.macOS.targetVersion}');
    defs.add('-DENABLE_BITCODE=${appleArgs.enableBitcode ? "ON" : "OFF"}');
    defs.add('-DENABLE_ARC=${appleArgs.enableArc ? "ON" : "OFF"}');
    defs.add('-DENABLE_VISIBILITY=${appleArgs.enableVisibility ? "ON" : "OFF"}');
    defs.add('-DENABLE_STRICT_TRY_COMPILE=${appleArgs.enableStrictTryCompile ? "ON" : "OFF"}');
    return defs;
  }

  Future<List<String>> _generateIOSDefines() async {
    if (codeConfig.targetOS != OS.iOS) {
      return [];
    }
    final defs = <String>[];
    final targetIosSdk = codeConfig.iOS.targetSdk;
    final targetIOSVersion = codeConfig.iOS.targetVersion;
    final toolchain = await iosToolchainCmake();
    defs.add('-DCMAKE_TOOLCHAIN_FILE=${toolchain.normalizePath().toFilePath()}');
    final platform = iosPlatforms[codeConfig.targetArchitecture]?[targetIosSdk];
    assert(platform != null, 'Unsupported iOS architecture: ${codeConfig.targetArchitecture}');
    defs.add('-DPLATFORM=$platform');
    defs.add('-DDEPLOYMENT_TARGET=$targetIOSVersion');
    defs.add('-DENABLE_BITCODE=${appleArgs.enableBitcode ? "ON" : "OFF"}');
    defs.add('-DENABLE_ARC=${appleArgs.enableArc ? "ON" : "OFF"}');
    defs.add('-DENABLE_VISIBILITY=${appleArgs.enableVisibility ? "ON" : "OFF"}');
    defs.add('-DENABLE_STRICT_TRY_COMPILE=${appleArgs.enableStrictTryCompile ? "ON" : "OFF"}');
    return defs;
  }

  Future<List<String>> _generateAndroidDefines() async {
    if (codeConfig.targetOS != OS.android) {
      return [];
    }
    final defs = <String>[];
    final toolchain = await androidToolchainCmake();
    defs.add('-DCMAKE_TOOLCHAIN_FILE=${toolchain.normalizePath().toFilePath()}');

    generator == Generator.defaultGenerator ? generator = Generator.ninja : generator = generator;

    // The Android Gradle plugin does not honor API level 19 and 20 when
    // invoking clang. Mimic that behavior here.
    // See https://github.com/dart-lang/native/issues/171.
    final minimumApi = codeConfig.targetArchitecture == Architecture.riscv64 ? 35 : 21;
    final _androidAPI = androidArgs.androidAPI ?? max(codeConfig.android.targetNdkApi, minimumApi);
    final _androidABI = androidArgs.androidABI ?? androidAbis[codeConfig.targetArchitecture];
    defs.add('-DANDROID_PLATFORM=android-$_androidAPI');
    defs.add('-DANDROID_ABI=$_androidABI');
    defs.add('-DANDROID_STL=${androidArgs.androidSTL}');
    defs.add('-DANDROID_ARM_NEON=${androidArgs.androidArmNeon}');

    return defs;
  }

  Future<List<String>> _generateWindowsDefines() async {
    if (codeConfig.targetOS != OS.windows) {
      return [];
    }
    final defs = <String>[];
    defs.add('-DCMAKE_SYSTEM_NAME=Windows');

    // Generators besides Visual Studio do not support the -A argument.
    if (generator == Generator.defaultGenerator || generator.name.startsWith("Visual Studio")) {
      if (codeConfig.targetArchitecture == Architecture.arm64) {
        defs.add('-DCMAKE_SYSTEM_PROCESSOR=ARM64');
        defs.addAll(['-A', 'ARM64']);
      }
      if (codeConfig.targetArchitecture == Architecture.x64) {
        defs.add('-DCMAKE_SYSTEM_PROCESSOR=AMD64');
        defs.addAll(['-A', 'x64']);
      }
      if (codeConfig.targetArchitecture == Architecture.ia32) {
        defs.add('-DCMAKE_SYSTEM_PROCESSOR=X86');
        defs.addAll(['-A', 'Win32']);
      }
    }
    return defs;
  }

  Future<List<String>> _generateLinuxDefines() async {
    if (codeConfig.targetOS != OS.linux) {
      return [];
    }
    final defs = <String>[];
    defs.add('-DCMAKE_SYSTEM_NAME=Linux');
    final toolchain = await linuxToolchainCmake();
    defs.add('-DCMAKE_TOOLCHAIN_FILE=${toolchain.normalizePath().toFilePath()}');
    return defs;
  }

  /// Returns the exit code of the last CMake generate command.
  ///
  /// -1: not exist
  /// 0: success
  /// other: failed
  Future<int> getLastGenExitCode() async {
    final statusFile = File.fromUri(outDir.resolve(lastGenStatusFile));
    if (!await statusFile.exists()) {
      return -1;
    }
    final content = await statusFile.readAsLines();
    final exitCode = int.tryParse(
      content.firstWhere((line) => line.startsWith('exitCode: ')).split('exitCode: ')[1],
    );
    return exitCode ?? -1;
  }

  static const androidAbis = {
    Architecture.arm: 'armeabi-v7a',
    Architecture.arm64: 'arm64-v8a',
    Architecture.ia32: 'x86',
    Architecture.x64: 'x86_64',
  };

  static const macosPlatforms = {Architecture.arm64: 'MAC_ARM64', Architecture.x64: 'MAC'};

  static const iosPlatforms = {
    Architecture.arm64: {IOSSdk.iPhoneOS: 'OS64', IOSSdk.iPhoneSimulator: 'SIMULATORARM64'},
    Architecture.x64: {IOSSdk.iPhoneSimulator: 'SIMULATOR64'},
  };
}
