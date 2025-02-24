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
import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets.dart';

import '../native_toolchain/android_ndk.dart';
import '../native_toolchain/cmake.dart';
import '../native_toolchain/xcode.dart';
import '../tool/tool_instance.dart';
import '../utils/package_config_parser.dart';
import '../utils/run_process.dart';
import 'build_mode.dart';
import 'generator.dart';
import 'log_level.dart';

class RunCMakeBuilder {
  final HookInput input;
  final CodeConfig codeConfig;
  final Logger? logger;
  final Uri sourceDir;
  final Uri outDir;

  final Map<String, String?> defines;
  final BuildMode buildMode;
  Generator? generator;
  Generator get defaultGenerator => switch (codeConfig.targetOS) {
        OS.android => Generator.ninja,
        OS.linux => Generator.make,
        OS.macOS => Generator.make,
        OS.iOS => Generator.xcode,
        _ => Generator.defaultGenerator,
      };

  final List<String>? targets;

  // ios.toolchain.cmake
  // https://github.com/leetal/ios-cmake?tab=readme-ov-file#exposed-variables
  final bool enableBitcode;
  final bool enableArc;
  final bool enableVisibility;
  final bool enableStrictTryCompile;

  // android ndk
  int? androidAPI;
  String? androidABI;
  String? androidSTL;
  final bool androidArmNeon;

  /// log level of CMake
  final LogLevel logLevel;

  RunCMakeBuilder({
    required this.input,
    required this.codeConfig,
    required this.sourceDir,
    this.logger,
    this.defines = const {},
    this.generator,
    this.buildMode = BuildMode.release,
    this.targets,
    this.enableBitcode = false,
    this.enableArc = true,
    this.enableVisibility = false,
    this.enableStrictTryCompile = false,
    this.androidAPI,
    this.androidABI,
    this.androidArmNeon = true,
    this.androidSTL = 'c++_static',
    this.logLevel = LogLevel.STATUS,
  }) : outDir = input.outputDirectory {
    generator ??= defaultGenerator;
  }

  Future<Uri> cmakePath() async {
    final cmakeTools = await cmake.defaultResolver?.resolve(logger: logger);
    final path = cmakeTools?.first.uri;
    assert(path != null);
    return Future.value(path);
  }

  Future<Uri> currentPackageRoot() async => Uri.directory(await getPackagePath("native_toolchain_cmake"));

  Future<Uri> iosToolchainCmake() async => (await currentPackageRoot()).resolve('cmake/ios.toolchain.cmake');

  Future<Uri> androidToolchainCmake() async {
    final tool = await androidNdk.defaultResolver?.resolve(logger: logger);
    final toolUri = tool?.first.uri.resolve('build/cmake/android.toolchain.cmake');
    assert(toolUri != null);
    return Future.value(toolUri);
  }

  Future<Uri> linuxToolchainCmake() async => switch (codeConfig.targetArchitecture) {
        Architecture.x64 => (await currentPackageRoot()).resolve('cmake/x86_64-linux-gnu.toolchain.cmake'),
        Architecture.arm64 => (await currentPackageRoot()).resolve('cmake/aarch64-linux-gnu.toolchain.cmake'),
        Architecture.riscv64 =>
          (await currentPackageRoot()).resolve('cmake/riscv64-linux-gnu.toolchain.cmake'),
        _ => throw UnimplementedError('Unsupported architecture: ${codeConfig.targetArchitecture} for Linux'),
      };

  Future<Uri> iosSdk(IOSSdk iosSdk, {required Logger? logger}) async {
    if (iosSdk == IOSSdk.iPhoneOS) {
      return (await iPhoneOSSdk.defaultResolver!.resolve(logger: logger))
          .where((i) => i.tool == iPhoneOSSdk)
          .first
          .uri;
    }
    assert(iosSdk == IOSSdk.iPhoneSimulator);
    return (await iPhoneSimulatorSdk.defaultResolver!.resolve(logger: logger))
        .where((i) => i.tool == iPhoneSimulatorSdk)
        .first
        .uri;
  }

  Future<Uri> macosSdk({required Logger? logger}) async =>
      (await macosxSdk.defaultResolver!.resolve(logger: logger)).where((i) => i.tool == macosxSdk).first.uri;

  Uri androidSysroot(ToolInstance compiler) => compiler.uri.resolve('../sysroot/');

  Future<void> run({Map<String, String>? environment}) async {
    await _generate(environment: environment);
    await _build(environment: environment);
  }

  Future<void> _generate({Map<String, String>? environment}) async {
    final windowsDefs = await _generateWindowsDefines();
    final linuxDefs = await _generateLinuxDefines();
    final macosDefs = await _generateMacosDefines();
    final iosDefs = await _generateIOSDefines();
    final androidDefs = await _generateAndroidDefines();
    final _defines = <String>[
      '-DCMAKE_BUILD_TYPE=${buildMode.name.toCapitalCase()}',
      if (buildMode == BuildMode.debug) '-DCMAKE_C_FLAGS_DEBUG="-DDEBUG"',
      if (buildMode == BuildMode.debug) '-DCMAKE_CXX_FLAGS_DEBUG="-DDEBUG"',
      ...windowsDefs,
      ...linuxDefs,
      ...macosDefs,
      ...iosDefs,
      ...androidDefs,
    ];

    final _generator = generator == Generator.defaultGenerator ? <String>[] : ['-G', generator!.name];

    defines.forEach((k, v) => _defines.add('-D$k=${v ?? "1"}'));

    await runProcess(
      executable: await cmakePath(),
      arguments: [
        '--log-level',
        logLevel.name,
        '-S',
        sourceDir.toFilePath(),
        '-B',
        outDir.toFilePath(windows: Platform.isWindows),
        ..._generator,
        ..._defines,
      ],
      logger: logger,
      captureOutput: true,
      throwOnUnexpectedExitCode: true,
      environment: environment,
    );
  }

  Future<void> _build({Map<String, String>? environment}) async {
    await runProcess(
      executable: await cmakePath(),
      arguments: [
        '--build',
        outDir.toFilePath(windows: Platform.isWindows),
        '--config',
        buildMode.name.toCapitalCase(),
        if (targets?.isNotEmpty ?? false) '--target',
        if (targets?.isNotEmpty ?? false) ...targets!,
      ],
      logger: logger,
      captureOutput: true,
      throwOnUnexpectedExitCode: true,
      environment: environment,
    );
  }

  Future<List<String>> _generateMacosDefines() async {
    if (codeConfig.targetOS != OS.macOS) {
      return [];
    }
    final definesMacos = <String>[];
    final toolchain = await iosToolchainCmake();
    definesMacos.add('-DCMAKE_TOOLCHAIN_FILE=${toolchain.toFilePath()}');
    final platform = macosPlatforms[codeConfig.targetArchitecture];
    assert(platform != null, 'Unsupported macOS architecture: ${codeConfig.targetArchitecture}');
    definesMacos.add('-DPLATFORM=$platform');
    definesMacos.add('-DDEPLOYMENT_TARGET=${codeConfig.macOS.targetVersion}');
    definesMacos.add('-DENABLE_BITCODE=${enableBitcode ? "ON" : "OFF"}');
    definesMacos.add('-DENABLE_ARC=${enableArc ? "ON" : "OFF"}');
    definesMacos.add('-DENABLE_VISIBILITY=${enableVisibility ? "ON" : "OFF"}');
    definesMacos.add('-DENABLE_STRICT_TRY_COMPILE=${enableStrictTryCompile ? "ON" : "OFF"}');
    return definesMacos;
  }

  Future<List<String>> _generateIOSDefines() async {
    if (codeConfig.targetOS != OS.iOS) {
      return [];
    }
    final definesIos = <String>[];
    final targetIosSdk = codeConfig.iOS.targetSdk;
    final targetIOSVersion = codeConfig.iOS.targetVersion;
    final toolchain = await iosToolchainCmake();
    definesIos.add('-DCMAKE_TOOLCHAIN_FILE=${toolchain.toFilePath()}');
    final platform = iosPlatforms[codeConfig.targetArchitecture]?[targetIosSdk];
    assert(platform != null, 'Unsupported iOS architecture: ${codeConfig.targetArchitecture}');
    definesIos.add('-DPLATFORM=$platform');
    definesIos.add('-DDEPLOYMENT_TARGET=$targetIOSVersion');
    definesIos.add('-DENABLE_BITCODE=${enableBitcode ? "ON" : "OFF"}');
    definesIos.add('-DENABLE_ARC=${enableArc ? "ON" : "OFF"}');
    definesIos.add('-DENABLE_VISIBILITY=${enableVisibility ? "ON" : "OFF"}');
    definesIos.add('-DENABLE_STRICT_TRY_COMPILE=${enableStrictTryCompile ? "ON" : "OFF"}');
    return definesIos;
  }

  Future<List<String>> _generateAndroidDefines() async {
    if (codeConfig.targetOS != OS.android) {
      return [];
    }
    final definesAndroid = <String>[];
    final toolchain = await androidToolchainCmake();
    definesAndroid.add('-DCMAKE_TOOLCHAIN_FILE=${toolchain.toFilePath()}');

    // The Android Gradle plugin does not honor API level 19 and 20 when
    // invoking clang. Mimic that behavior here.
    // See https://github.com/dart-lang/native/issues/171.
    final minimumApi = codeConfig.targetArchitecture == Architecture.riscv64 ? 35 : 21;
    androidAPI ??= max(codeConfig.android.targetNdkApi, minimumApi);
    androidABI ??= androidAbis[codeConfig.targetArchitecture];
    definesAndroid.add('-DANDROID_PLATFORM=android-$androidAPI');
    definesAndroid.add('-DANDROID_ABI=${androidAbis[codeConfig.targetArchitecture]}');

    if (androidSTL != null) {
      definesAndroid.add('-DANDROID_STL=$androidSTL');
    }
    definesAndroid.add('-DANDROID_ARM_NEON=$androidArmNeon');

    return definesAndroid;
  }

  Future<List<String>> _generateWindowsDefines() async {
    if (codeConfig.targetOS != OS.windows) {
      return [];
    }
    final definesWindows = <String>[];
    definesWindows.add('-DCMAKE_SYSTEM_NAME=Windows');

    if (codeConfig.targetArchitecture == Architecture.arm64) {
      definesWindows.add('-DCMAKE_SYSTEM_PROCESSOR=ARM64');
      definesWindows.addAll(['-A', 'ARM64']);
    }
    if (codeConfig.targetArchitecture == Architecture.x64) {
      definesWindows.add('-DCMAKE_SYSTEM_PROCESSOR=AMD64');
      definesWindows.addAll(['-A', 'x64']);
    }
    if (codeConfig.targetArchitecture == Architecture.ia32) {
      definesWindows.add('-DCMAKE_SYSTEM_PROCESSOR=X86');
      definesWindows.addAll(['-A', 'Win32']);
    }
    return definesWindows;
  }

  Future<List<String>> _generateLinuxDefines() async {
    if (codeConfig.targetOS != OS.linux) {
      return [];
    }
    final definesLinux = <String>[];
    definesLinux.add('-DCMAKE_SYSTEM_NAME=Linux');
    final toolchain = await linuxToolchainCmake();
    definesLinux.add('-DCMAKE_TOOLCHAIN_FILE=${toolchain.toFilePath()}');
    return definesLinux;
  }

  static const androidAbis = {
    Architecture.arm: 'armeabi-v7a',
    Architecture.arm64: 'arm64-v8a',
    Architecture.ia32: 'x86',
    Architecture.x64: 'x86_64',
  };

  static const macosPlatforms = {
    Architecture.arm64: 'MAC_ARM64',
    Architecture.x64: 'MAC',
  };

  static const iosPlatforms = {
    Architecture.arm64: {
      IOSSdk.iPhoneOS: 'OS64',
      IOSSdk.iPhoneSimulator: 'SIMULATORARM64',
    },
    Architecture.x64: {
      IOSSdk.iPhoneSimulator: 'SIMULATOR64',
    },
  };

  static const clangWindowsTargetFlags = {
    Architecture.arm64: 'arm64-pc-windows-msvc',
    Architecture.ia32: 'i386-pc-windows-msvc',
    Architecture.x64: 'x86_64-pc-windows-msvc',
  };

  static const cmakeLinuxToolchains = {
    Architecture.arm64: 'arm64-linux-gnu',
    Architecture.x64: 'x86_64-linux-gnu',
    Architecture.riscv64: 'riscv64-linux-gnu',
  };
}
