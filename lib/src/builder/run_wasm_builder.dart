// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:io';

import 'package:change_case/change_case.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../native_toolchain/cmake.dart';
import '../native_toolchain/emscripten.dart';
import '../native_toolchain/ninja.dart';
import '../tool/tool_instance.dart';
import '../utils/run_process.dart';
import 'build_mode.dart';
import 'builder_args.dart';
import 'generator.dart';
import 'log_level.dart';
import 'user_config.dart';

/// Runs CMake with the Emscripten toolchain and returns the emitted
/// `.js`/`.wasm` files.
class RunCMakeWasmBuilder {
  final String name;
  final Uri sourceDir;
  final Uri outDir;
  final Map<String, String?> defines;
  final List<String> linkerFlags;
  final bool singleFile;
  final BuildMode buildMode;
  final Generator generator;
  final List<String>? targets;
  final LogLevel logLevel;
  final Logger? logger;
  final UserConfig userConfig;
  final EmscriptenBuilderArgs emscriptenArgs;
  final int? parallelJobs;
  final Map<String, String>? environment;
  final String lastGenStatusFile;

  RunCMakeWasmBuilder({
    required this.name,
    required this.sourceDir,
    required this.outDir,
    required this.userConfig,
    this.defines = const {},
    this.linkerFlags = const [],
    this.singleFile = false,
    this.buildMode = BuildMode.release,
    this.generator = Generator.ninja,
    this.targets,
    this.logLevel = LogLevel.STATUS,
    this.logger,
    this.emscriptenArgs = const EmscriptenBuilderArgs(),
    int? parallelJobs,
    bool parallelUseAllProcessors = false,
    this.environment,
    this.lastGenStatusFile = 'ntc_last_generate_status.txt',
  }) : parallelJobs = parallelJobs ?? (parallelUseAllProcessors ? Platform.numberOfProcessors : null);

  Map<String, String> get _environment {
    final env = Map<String, String>.from(environment ?? Platform.environment);
    final emsdkPath = emscriptenArgs.emsdkPath ?? userConfig.emsdkPath;
    if (emsdkPath != null) env['EMSDK'] ??= emsdkPath;
    return env;
  }

  Future<({List<File> artifacts, ToolInstance emcc, Uri toolchainFile})> build() async {
    final env = _environment;
    final cmakeInstance = await _resolveCmake(env);
    final ninjaInstance = await _resolveNinja(env);
    final emscripten = await resolveEmscripten(
      userConfig: userConfig,
      args: emscriptenArgs,
      logger: logger,
      environment: env,
    );

    await _generate(
      cmake: cmakeInstance.uri,
      ninja: ninjaInstance,
      toolchainFile: emscripten.toolchainFile,
      environment: env,
    );
    await _build(cmake: cmakeInstance, environment: env);

    return (
      artifacts: await _collectArtifacts(),
      emcc: emscripten.emcc,
      toolchainFile: emscripten.toolchainFile,
    );
  }

  Future<ToolInstance> _resolveCmake(Map<String, String> env) async {
    final tools = await cmake.defaultResolver!.resolve(
      logger: logger,
      userConfig: userConfig,
      environment: env,
    );
    if (tools.isEmpty) {
      throw Exception('Failed to resolve CMake.');
    }
    return tools.first;
  }

  Future<ToolInstance> _resolveNinja(Map<String, String> env) async {
    final tools = await ninja.defaultResolver!.resolve(
      logger: logger,
      userConfig: userConfig,
      environment: env,
    );
    if (tools.isEmpty) {
      throw Exception(
        'Failed to resolve Ninja. Emscripten builds require Ninja '
        '(install it or set user_defines.ninja_version).',
      );
    }
    return tools.first;
  }

  Future<void> _generate({
    required Uri cmake,
    required ToolInstance ninja,
    required Uri toolchainFile,
    required Map<String, String> environment,
  }) async {
    final effectiveGenerator = generator == Generator.defaultGenerator ? Generator.ninja : generator;
    if (effectiveGenerator.name.startsWith('Visual Studio')) {
      throw ArgumentError(
        'Emscripten builds cannot use the Visual Studio CMake generator. '
        'Use Generator.ninja instead.',
      );
    }

    final remainingDefines = Map<String, String?>.from(defines);
    final existingLinkerFlags = remainingDefines.remove('CMAKE_EXE_LINKER_FLAGS');
    final linkerFlagString = [
      if (existingLinkerFlags != null && existingLinkerFlags.isNotEmpty) existingLinkerFlags,
      ...linkerFlags,
      if (singleFile) '-sSINGLE_FILE=1',
    ].join(' ');

    final ninjaBinary = ninja.uri.toFilePath();
    final ninjaDir = File.fromUri(ninja.uri).parent.path;

    final args = <String>[
      '--log-level=${logLevel.name}',
      '-S',
      sourceDir.normalizePath().toFilePath(),
      '-B',
      outDir.normalizePath().toFilePath(),
      '-G',
      effectiveGenerator.name,
      '-DCMAKE_BUILD_TYPE=${buildMode.name.toCapitalCase()}',
      '-DCMAKE_TOOLCHAIN_FILE=${toolchainFile.normalizePath().toFilePath()}',
      '-DCMAKE_MAKE_PROGRAM=$ninjaBinary',
      '-DCMAKE_PROGRAM_PATH=$ninjaDir',
      // Always pass this, even when empty: otherwise a previous
      // singleFile build leaves `-sSINGLE_FILE=1` in CMakeCache.txt and the
      // next separate build keeps embedding the wasm.
      '-DCMAKE_EXE_LINKER_FLAGS=$linkerFlagString',
      for (final entry in remainingDefines.entries) '-D${entry.key}=${entry.value ?? '1'}',
    ];

    logger?.fine('CMake (Emscripten) configure: $args');
    final result = await runProcess(
      executable: cmake,
      arguments: args,
      workingDirectory: outDir,
      logger: logger,
      captureOutput: true,
      throwOnUnexpectedExitCode: false,
      environment: environment,
    );

    final status =
        'command: ${result.command}\n'
        'exitCode: ${result.exitCode}\n';
    try {
      await File.fromUri(outDir.resolve(lastGenStatusFile)).writeAsString(status);
    } on FileSystemException {
      // The output directory may not exist if CMake failed early.
    }

    if (result.exitCode != 0) {
      throw Exception(
        'Failed to generate the Emscripten CMake project: '
        '${_processOutput(result)}',
      );
    }
  }

  Future<void> _build({required ToolInstance cmake, required Map<String, String> environment}) async {
    final parallel = <String>[];
    if (parallelJobs != null && cmake.version != null && cmake.version! > Version.parse('3.12.0')) {
      parallel.addAll(['--parallel', parallelJobs.toString()]);
    }

    final result = await runProcess(
      executable: cmake.uri,
      arguments: [
        '--build',
        outDir.normalizePath().toFilePath(),
        '--config',
        buildMode.name.toCapitalCase(),
        if (targets?.isNotEmpty ?? false) '--target',
        if (targets?.isNotEmpty ?? false) ...targets!,
        ...parallel,
      ],
      workingDirectory: outDir,
      logger: logger,
      captureOutput: true,
      throwOnUnexpectedExitCode: false,
      environment: environment,
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Failed to build the Emscripten CMake project: '
        '${_processOutput(result)}',
      );
    }
  }

  static String _processOutput(RunProcessResult result) {
    final output = '${result.stdout} ${result.stderr}'.trim();
    const limit = 4000;
    return output.length <= limit ? output : output.substring(output.length - limit);
  }

  Future<List<File>> _collectArtifacts() async {
    final js = await _findArtifact('$name.js');
    if (js == null) {
      throw Exception(
        'CMake did not produce $name.js in ${outDir.toFilePath()}. '
        'Emscripten targets must be executables (add_executable) and name '
        'their output "$name".',
      );
    }

    final artifacts = <File>[js];
    if (!singleFile) {
      final wasm = await _findArtifact('$name.wasm');
      if (wasm == null) {
        throw Exception(
          'CMake did not produce $name.wasm in ${outDir.toFilePath()}. '
          'Use `-sSINGLE_FILE=1` via CMakeWasmBuilder.singleFile if you '
          'intentionally embed the wasm in the JavaScript file.',
        );
      }
      final bytes = await wasm.readAsBytes();
      if (bytes.length < 4 || bytes[0] != 0x00 || bytes[1] != 0x61 || bytes[2] != 0x73 || bytes[3] != 0x6D) {
        throw Exception('${wasm.path} is not a WebAssembly module (missing \\0asm magic).');
      }
      artifacts.add(wasm);
    }

    logger?.info('Emscripten artifacts: ${artifacts.map((e) => e.path).join(', ')}');
    return artifacts;
  }

  Future<File?> _findArtifact(String fileName) async {
    final direct = File.fromUri(outDir.resolve(fileName));
    if (await direct.exists()) return direct;

    final directory = Directory.fromUri(outDir);
    if (!await directory.exists()) return null;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.uri.pathSegments.last == fileName) {
        return entity;
      }
    }
    return null;
  }
}
