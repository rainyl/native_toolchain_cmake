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
  final Uri sourceDir;

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

  /// log level of CMake
  final LogLevel logLevel;

  CMakeBuilder.create({
    required this.name,
    required this.sourceDir,
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
  });

  /// Runs the C Compiler with on this C build spec.
  ///
  /// Completes with an error if the build fails.
  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
    Map<String, String> environment = const {},
  }) async {
    final outDir = input.outputDirectory;
    await Directory.fromUri(outDir).create(recursive: true);
    final task = RunCMakeBuilder(
      input: input,
      codeConfig: input.config.code,
      logger: logger,
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
    envVars.addAll(environment);
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
