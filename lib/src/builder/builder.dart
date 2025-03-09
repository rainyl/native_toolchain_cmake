// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
//
// This file is adapted from https://github.com/dart-lang/native/tree/main/pkgs/native_toolchain_c
// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';

import '../utils/run_process.dart';
import 'build_mode.dart';
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

  /// Sources directory
  Uri sourceDir;

  /// Output directory
  Uri? outDir;

  /// Definitions of preprocessor macros.
  ///
  /// When the value is `null`, the macro is defined without a value.
  final Map<String, String?> defines;

  /// If the code asset should be a dynamic or static library.
  ///
  /// This determines whether to produce a dynamic or static library. If null,
  /// the value is instead retrieved from the [LinkInput].
  final LinkModePreference? linkModePreference;

  final BuildMode buildMode;

  final List<String>? targets;
  final Generator generator;
  final String? toolset;

  // ios.toolchain.cmake
  // https://github.com/leetal/ios-cmake?tab=readme-ov-file#exposed-variables
  final bool enableBitcode;
  final bool enableArc;
  final bool enableVisibility;
  final bool enableStrictTryCompile;

  // android ndk
  int? androidAPI;
  String? androidABI;
  final String androidSTL;
  final bool androidArmNeon;

  final Logger? logger;

  /// log level of CMake
  final LogLevel logLevel;

  /// If true, a build will be performed in the local directory.
  final bool buildLocal;

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
  /// - [linkModePreference]: Preferences for linking the built asset.
  ///   [LinkModePreference.dynamic] or [LinkModePreference.static].
  /// - [buildMode]: The build mode to use. Defaults to [BuildMode.release].
  /// - [targets]: An optional list with the target to install.
  /// - [generator]: The CMake generator to use.
  ///   Defaults to [Generator.defaultGenerator].
  /// - [toolset]: An optional toolset string for CMake.
  /// - [enableBitcode]: Flag to enable Bitcode; defaults to `false`.
  /// - [enableArc]: Flag to enable ARC; defaults to `true`.
  /// - [enableVisibility]: Flag to enable visibility, necessary to expose
  ///   symbols; defaults to `true`.
  /// - [enableStrictTryCompile]: Flag to enable strict try-compile mode;
  ///    defaults to `false`.
  /// - [androidAPI]: (Optional) The Android API level.
  /// - [androidABI]: (Optional) The Android ABI specification.
  /// - [androidArmNeon]: Flag that indicates whether ARM NEON is enabled;
  ///    defaults to `true`.
  /// - [androidSTL]: The Android STL type; defaults to `'c++_static'`.
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
    this.linkModePreference,
    this.buildMode = BuildMode.release,
    this.targets,
    this.generator = Generator.defaultGenerator,
    this.toolset,
    this.enableBitcode = false,
    this.enableArc = true,
    this.enableVisibility = true, // necessary to expose symbols
    this.enableStrictTryCompile = false,
    this.androidAPI,
    this.androidABI,
    this.androidArmNeon = true,
    this.androidSTL = 'c++_static',
    this.logLevel = LogLevel.STATUS,
    this.logger,
    this.buildLocal = false,
  });

  /// This constructor initializes a new build config by cloning the
  /// repository from [gitUrl] into a subdirectory under [sourceDir].
  ///
  /// Parameters:
  /// - [name]: The name of the library or executable to build or link.
  ///   This determines the final file name according to target OS naming
  ///   conventions.
  /// - [gitUrl]: The URL of the Git repository to clone.
  ///   e.x. https://github.com/rainyl/native_toolchain_cmake.git
  /// - [sourceDir]: The base directory URI where the repository will be cloned.
  /// - [outDir]: (Optional) The output directory URI. If not provided,
  ///    will be derived from the build hook's input.outputDirectory.
  /// - [gitBranch]: The branch name to clone; defaults to `'main'`.
  /// - [gitCommit]: The commit hash to reset to after cloning;
  ///   defaults to `'HEAD'`. When `'HEAD'` is provided, the latest commit
  ///   from the shallow clone is used.
  /// - [gitSubDir]: (Optional) A subdirectory within the cloned repository
  ///   containing the source files. [sourceDir] will be updated to include it.
  /// - [defines]: A map specifying CMake preprocessor macros and their values.
  /// - [linkModePreference]: Preferences for linking the built asset.
  ///   [LinkModePreference.dynamic] or [LinkModePreference.static].
  /// - [buildMode]: The build mode to use. Defaults to [BuildMode.release].
  /// - [targets]: An optional list with the target to install.
  /// - [generator]: The CMake generator to use.
  ///   Defaults to [Generator.defaultGenerator].
  /// - [toolset]: An optional toolset string for CMake.
  /// - [enableBitcode]: Flag to enable Bitcode; defaults to `false`.
  /// - [enableArc]: Flag to enable ARC; defaults to `true`.
  /// - [enableVisibility]: Flag to enable visibility, necessary to expose
  ///   symbols; defaults to `true`.
  /// - [enableStrictTryCompile]: Flag to enable strict try-compile mode;
  ///    defaults to `false`.
  /// - [androidAPI]: (Optional) The Android API level.
  /// - [androidABI]: (Optional) The Android ABI specification.
  /// - [androidArmNeon]: Flag that indicates whether ARM NEON is enabled;
  ///    defaults to `true`.
  /// - [androidSTL]: The Android STL type; defaults to `'c++_static'`.
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
    String gitCommit = 'HEAD',
    String gitSubDir = '',
    this.defines = const {},
    this.linkModePreference,
    this.buildMode = BuildMode.release,
    this.targets,
    this.generator = Generator.defaultGenerator,
    this.toolset,
    this.enableBitcode = false,
    this.enableArc = true,
    this.enableVisibility = true, // necessary to expose symbols
    this.enableStrictTryCompile = false,
    this.androidAPI,
    this.androidABI,
    this.androidArmNeon = true,
    this.androidSTL = 'c++_static',
    this.logLevel = LogLevel.STATUS,
    this.logger,
    this.buildLocal = false,
  }) {
    // Some platforms will error if directory does not exist, create it.
    final newDir = Directory.fromUri(
      Uri.directory("${sourceDir.toFilePath()}/external/$name"),
    )..createSync(recursive: true);
    final dirPath = newDir.path;

    runProcessSync(
      executable: 'git',
      arguments: ['init'],
      workingDirectory: newDir.uri,
      throwOnUnexpectedExitCode: true,
      logger: logger,
    );

    final remoteAddProcess = Process.runSync(
      'git',
      [
        'remote',
        'add',
        'origin',
        gitUrl,
      ],
      workingDirectory: dirPath,
    );
    logger?.log(Level.INFO, 'git remote add: ${remoteAddProcess.stdout}');

    final fetchProcess = Process.runSync(
      'git',
      ['pull', '--depth=1', 'origin', gitBranch, gitCommit],
      workingDirectory: dirPath,
    );
    logger?.log(Level.INFO, 'git fetch: ${fetchProcess.stdout}');

    final resetProcess = Process.runSync(
      'git',
      [
        'reset',
        '--hard',
        gitCommit,
      ],
      workingDirectory: dirPath,
    );
    logger?.log(Level.INFO, 'git reset: ${resetProcess.stdout}');

    if (gitSubDir.isNotEmpty) {
      sourceDir = Uri.directory(
        "${sourceDir.toFilePath()}/external/$name/$gitSubDir",
      );
    }
  }

  /// Runs the C Compiler with on this C build spec.
  ///
  /// Completes with an error if the build fails.
  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    Logger? logger,
  }) async {
    final _logger = logger ?? this.logger;

    if (buildLocal) {
      final plat = input.config.code.targetOS.name.toLowerCase();
      final arch = input.config.code.targetArchitecture.name.toLowerCase();
      outDir = sourceDir.resolve('build/$plat/$arch');
    }

    await Directory.fromUri(outDir ?? input.outputDirectory)
        .create(recursive: true);
    final task = RunCMakeBuilder(
      input: input,
      outputDir: outDir ?? input.outputDirectory,
      codeConfig: input.config.code,
      logger: _logger,
      sourceDir: sourceDir,
      generator: generator,
      buildMode: buildMode,
      defines: defines,
      targets: targets,
      enableArc: enableArc,
      enableBitcode: enableBitcode,
      enableStrictTryCompile: enableStrictTryCompile,
      enableVisibility: enableVisibility,
      androidABI: androidABI,
      androidAPI: androidAPI,
      androidArmNeon: androidArmNeon,
      androidSTL: androidSTL,
      logLevel: logLevel,
    );

    final Map<String, String> envVars = Map.from(Platform.environment);
    // TODO: patch environment variables for cmake
    // may be error if system drive is not C:
    // https://github.com/dart-lang/native/issues/2077
    if (input.config.code.targetOS == OS.windows) {
      envVars.addAll({
        "WINDIR": r"C:\WINDOWS",
        "SYSTEMDRIVE": "C:",
      });
    }
    await task.run(environment: envVars);
  }
}
