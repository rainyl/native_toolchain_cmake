// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
//
// This file is adapted from https://github.com/dart-lang/native/tree/main/pkgs/native_toolchain_c
// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

import '../native_toolchain/msvc.dart';
import '../utils/env_from_bat.dart';
import '../utils/run_process.dart';
import 'build_mode.dart';
import 'builder_args.dart';
import 'generator.dart';
import 'log_level.dart';
import 'run_builder.dart';

/// Specification for building an artifact with a C compiler.
class CMakeBuilder implements Builder {
  /// Name of the library or executable to build or link.
  ///
  /// The filename will be decided by [CodeConfig.targetOS] and
  /// [OSLibraryNaming.libraryFileName] or
  /// [OSLibraryNaming.executableFileName].
  ///
  /// File will be placed in [LinkInput.outputDirectory].
  final String name;

  /// Sources directory, for [CMakeBuilder.create], it should be the directory containing
  /// the `CMakeLists.txt`, for [CMakeBuilder.fromGit], it should be the directory where the
  /// repository will be cloned, and the repository will be cloned to [sourceDir]/external/[name].
  final Uri sourceDir;

  /// internel use, point to the directory containing `CMakeLists.txt`.
  Uri cmakeListsDir;

  /// Output directory, if not provided:
  ///   - if [buildLocal] is true, it will be `{sourceDir}/build/{platform}/{arch}`.
  ///   - else it will be derived from the build hook's `input.outputDirectory`.
  Uri? outDir;

  /// Definitions of preprocessor macros.
  ///
  /// When the value is `null`, the macro is defined without a value.
  final Map<String, String?> defines;

  final BuildMode buildMode;

  final List<String>? targets;
  final Generator generator;
  final String? toolset;

  // ios.toolchain.cmake
  final AppleBuilderArgs appleArgs;

  // android ndk
  final AndroidBuilderArgs androidArgs;

  final Logger? logger;

  /// log level of CMake
  final LogLevel logLevel;

  /// If true, a build will be performed in `{sourceDir}/build/{platform}/{arch}`.
  final bool buildLocal;

  final bool useVcvars;

  /// This constructor initializes a new build config from [sourceDir].
  ///
  /// Parameters:
  /// - [name]: The name of the library or executable to build or link.
  ///   This determines the final file name according to target OS naming
  ///   conventions.
  /// - [sourceDir]: The base directory URI where the repository will be cloned.
  /// - [outDir]: (Optional) The output directory URI. If not provided,
  ///    will be derived from the build hook's input.outputDirectory.
  ///   containing the source files. [sourceDir] will be updated to include it.
  /// - [defines]: A map specifying CMake preprocessor macros and their values.
  /// - [buildMode]: The build mode to use. Defaults to [BuildMode.release].
  /// - [targets]: An optional list with the target to install.
  /// - [generator]: The CMake generator to use.
  ///   Defaults to [Generator.defaultGenerator].
  /// - [toolset]: An optional toolset string for CMake.
  /// - [logLevel]: The verbosity level for CMake logging;
  ///    defaults to [LogLevel.STATUS].
  /// - [logger]: (Optional) A [Logger] for outputting log messages.
  /// - [buildLocal]: Flag indicating if the build should be performed locally;
  ///   defaults to `false`.
  CMakeBuilder.create({
    required this.name,
    required this.sourceDir,
    this.outDir,
    this.defines = const {},
    this.buildMode = BuildMode.release,
    this.targets,
    this.generator = Generator.defaultGenerator,
    this.toolset,
    this.logLevel = LogLevel.STATUS,
    this.logger,
    this.buildLocal = false,
    this.androidArgs = const AndroidBuilderArgs(),
    this.appleArgs = const AppleBuilderArgs(),
    this.useVcvars = true,
  }) : cmakeListsDir = sourceDir;

  /// This constructor initializes a new build config by cloning the
  /// repository from [gitUrl] into a subdirectory under [sourceDir].
  ///
  /// Parameters:
  /// - [name]: The name of the library or executable to build or link.
  ///   This determines the final file name according to target OS naming
  ///   conventions.
  /// - [gitUrl]: The URL of the Git repository to clone.
  ///   e.x. https://github.com/rainyl/native_toolchain_cmake.git
  /// - [sourceDir]: The base directory URI, the repository will be cloned to [sourceDir]/external/[name].
  /// - [outDir]: (Optional) The output directory URI. If not provided,
  ///    will be derived from the build hook's input.outputDirectory.
  /// - [gitBranch]: The branch name to clone; defaults to `'main'`.
  /// - [gitCommit]: The commit hash to reset to after cloning;
  ///   defaults to `'HEAD'`. When `'HEAD'` is provided, the latest commit
  ///   from the shallow clone is used.
  /// - [gitSubDir]: (Optional) A subdirectory within the cloned repository
  ///   containing the source files. [sourceDir] will be updated to include it.
  /// - [defines]: A map specifying CMake preprocessor macros and their values.
  /// - [buildMode]: The build mode to use. Defaults to [BuildMode.release].
  /// - [targets]: An optional list with the target to install.
  /// - [generator]: The CMake generator to use.
  ///   Defaults to [Generator.defaultGenerator].
  /// - [toolset]: An optional toolset string for CMake.
  /// - [logLevel]: The verbosity level for CMake logging;
  ///    defaults to [LogLevel.STATUS].
  /// - [logger]: (Optional) A [Logger] for outputting log messages.
  /// - [buildLocal]: Flag indicating if the build should be performed locally;
  ///   defaults to `false`.
  CMakeBuilder.fromGit({
    required this.name,
    required String gitUrl,
    required this.sourceDir,
    this.outDir,
    String gitBranch = 'main',
    String gitCommit = 'FETCH_HEAD',
    String gitSubDir = '',
    this.defines = const {},
    this.buildMode = BuildMode.release,
    this.targets,
    this.generator = Generator.defaultGenerator,
    this.toolset,
    this.logLevel = LogLevel.STATUS,
    this.logger,
    this.buildLocal = false,
    this.androidArgs = const AndroidBuilderArgs(),
    this.appleArgs = const AppleBuilderArgs(),
    this.useVcvars = true,
  }) : cmakeListsDir = sourceDir {
    // Some platforms will error if directory does not exist, create it.
    cmakeListsDir = sourceDir.resolve('external/$name/').normalizePath();
    Directory.fromUri(cmakeListsDir).createSync(recursive: true);

    runProcessSync(
      executable: 'git',
      arguments: ['init'],
      workingDirectory: cmakeListsDir,
      throwOnUnexpectedExitCode: true,
      logger: logger,
    );

    runProcessSync(
      executable: 'git',
      arguments: ['remote', 'add', 'origin', gitUrl],
      workingDirectory: cmakeListsDir,
      throwOnUnexpectedExitCode: true,
      logger: logger,
    );
    runProcessSync(
      executable: 'git',
      arguments: ['fetch', 'origin', gitBranch],
      workingDirectory: cmakeListsDir,
      throwOnUnexpectedExitCode: true,
      logger: logger,
    );
    runProcessSync(
      executable: 'git',
      arguments: ['reset', '--hard', gitCommit],
      workingDirectory: cmakeListsDir,
      throwOnUnexpectedExitCode: true,
      logger: logger,
    );

    cmakeListsDir = cmakeListsDir.resolve(gitSubDir).normalizePath();
  }

  /// Runs the CMake genetate and build process.
  ///
  /// Completes with an error if the build fails.
  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    Logger? logger,
  }) async {
    // do not override user specified output directory if they also set buildLocal to true
    if (outDir == null && buildLocal) {
      final plat = input.config.code.targetOS.name.toLowerCase();
      final arch = input.config.code.targetArchitecture.name.toLowerCase();
      outDir = sourceDir.resolve('build/').resolve('$plat/').resolve(arch).normalizePath();
    }
    await Directory.fromUri(outDir ?? input.outputDirectory).create(recursive: true);

    final task = RunCMakeBuilder(
      input: input,
      outputDir: outDir,
      codeConfig: input.config.code,
      logger: logger ?? this.logger,
      sourceDir: cmakeListsDir,
      generator: generator,
      buildMode: buildMode,
      defines: defines,
      targets: targets,
      appleArgs: appleArgs,
      androidArgs: androidArgs,
      logLevel: logLevel,
    );

    // Do not remove this line for potential extra variables in the future
    final Map<String, String> envVars = Map.from(Platform.environment);
    if (useVcvars) {
      envVars.addAll(
        await environmentFromVcvars(
          targetOS: input.config.code.targetOS,
          targetArchitecture: input.config.code.targetArchitecture,
          logger: logger,
        ),
      );
    }
    await task.run(environment: envVars);
  }

  /// Get environment variables from vcvarsXXX.bat
  ///
  /// if [targetArchitecture] not provided, current architecture will be used
  Future<Map<String, String>> environmentFromVcvars({
    required OS targetOS,
    Architecture? targetArchitecture,
    Logger? logger,
  }) async {
    // TODO: patch environment variables for cmake
    // may be error if system drive is not C:
    // https://github.com/dart-lang/native/issues/2077
    final vars = {
      "WINDIR": r"C:\WINDOWS",
      "SYSTEMDRIVE": "C:",
    };

    if (targetOS != OS.windows) return {};
    targetArchitecture ??= Architecture.current;
    final vcvars = switch (targetArchitecture) {
      Architecture.x64 => vcvars64,
      Architecture.ia32 => vcvars32,
      Architecture.arm64 => vcvarsarm64,
      _ => throw UnsupportedError('Unsupported architecture: $targetArchitecture'),
    };
    final tools = await vcvars.defaultResolver!.resolve(logger: logger);
    if (tools.isNotEmpty) {
      final _vars = await environmentFromBatchFile(tools.first.uri);
      logger?.info('Environment variables from $vcvars: $vars');
      vars.addAll(_vars);
      return vars;
    }
    logger?.warning('No vcvars found for $targetOS $targetArchitecture');
    return {};
  }
}
