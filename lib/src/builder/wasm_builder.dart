// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import '../tool/tool_instance.dart';
import 'build_mode.dart';
import 'builder_args.dart';
import 'generator.dart';
import 'log_level.dart';
import 'run_wasm_builder.dart';
import 'user_config.dart';

/// Builds a CMake project with Emscripten and exposes the resulting
/// WebAssembly module to Dart/Flutter web.
///
/// Two modes are supported:
///
/// * **Build hook** ([run]): emits the generated files as [DataAsset]s.
///   This requires the Flutter/Dart tooling to support data assets. In Flutter
///   this is currently available on the `master` channel behind
///   `flutter config --enable-dart-data-assets`.
/// * **Standalone** ([runStandalone]): builds the files into a directory for
///   standard asset bundling or manual hosting. This also works on Flutter
///   stable and for pure Dart web.
///
/// The CMake project must produce an executable named [name] (`add.js` and,
/// unless [singleFile] is `true`, `add.wasm`). Typical CMake setup:
///
/// ```cmake
/// if(EMSCRIPTEN)
///   add_executable(add src/add.c)
///   target_link_options(add PRIVATE
///     "-sMODULARIZE=1"
///     "-sEXPORT_NAME=addModule"
///     "-sEXPORTED_FUNCTIONS=['_add']"
///     "-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap']"
///     "--no-entry")
/// endif()
/// ```
class CMakeWasmBuilder {
  /// Base name of the CMake target and of the emitted `.js`/`.wasm` files.
  final String name;

  /// Directory containing `CMakeLists.txt`.
  final Uri sourceDir;

  /// Optional CMake build directory. Defaults to a directory inside the hook
  /// output directory (or [sourceDir]/build/wasm in standalone mode when
  /// [buildLocal] is set).
  Uri? outDir;

  /// Extra `-D` definitions for CMake.
  final Map<String, String?> defines;

  /// Extra linker flags appended to `CMAKE_EXE_LINKER_FLAGS`, e.g.
  /// `-sEXPORTED_FUNCTIONS=['_foo']`.
  final List<String> linkerFlags;

  /// Embed the `.wasm` file in the generated JavaScript using
  /// `-sSINGLE_FILE=1`.
  ///
  /// In this mode only `<name>.js` is emitted and [run] exposes a single
  /// DataAsset.
  final bool singleFile;

  final BuildMode buildMode;
  final Generator generator;
  final List<String>? targets;
  final LogLevel logLevel;
  final Logger? logger;

  /// Build into `<sourceDir>/build/wasm` instead of [outDir] in standalone
  /// mode.
  final bool buildLocal;

  final EmscriptenBuilderArgs emscriptenArgs;
  final int? parallelJobs;
  final bool parallelUseAllProcessors;

  /// Environment for tool discovery and CMake. Defaults to the current
  /// process environment.
  final Map<String, String>? environment;

  /// Asset name prefix used for data assets, e.g. `wasm/` produces
  /// `wasm/add.js` and `wasm/add.wasm`.
  final String assetPrefix;

  CMakeWasmBuilder.create({
    required this.name,
    required Uri sourceDir,
    this.outDir,
    this.defines = const {},
    this.linkerFlags = const [],
    this.singleFile = false,
    this.buildMode = BuildMode.release,
    this.generator = Generator.ninja,
    this.targets,
    this.logLevel = LogLevel.STATUS,
    this.logger,
    this.buildLocal = false,
    this.emscriptenArgs = const EmscriptenBuilderArgs(),
    this.parallelJobs,
    this.parallelUseAllProcessors = false,
    this.environment,
    this.assetPrefix = 'wasm/',
  }) : sourceDir = sourceDir.isAbsolute ? sourceDir : Directory.fromUri(sourceDir).absolute.uri;

  /// Runs the Emscripten build for a `hook/build.dart` invocation and emits
  /// the generated files as data assets.
  ///
  /// This method is a no-op when code assets are requested (native targets) or
  /// when data assets are not requested (e.g. old tooling). Call it from the
  /// data-asset branch of your hook.
  Future<void> run({required BuildInput input, required BuildOutputBuilder output, Logger? logger}) async {
    final log = logger ?? this.logger;
    if (!input.config.buildDataAssets) {
      log?.info('No data assets requested; skipping Emscripten/WASM build.');
      return;
    }
    if (input.config.buildCodeAssets) {
      log?.info(
        'Code assets requested (native target); skipping Emscripten/WASM '
        'build. Use CMakeBuilder for native targets.',
      );
      return;
    }

    final userDefines = _parseUserDefines(input.json['user_defines'], log);
    final userConfig = UserConfig.parseFromUserDefines(
      targetOS: webOS,
      userDefines: userDefines,
      logger: log,
    );

    final buildDir = outDir ?? input.outputDirectory.resolve('cmake-wasm/');
    final result = await _build(buildDir, userConfig, log);

    for (final artifact in result.artifacts) {
      output.assets.data.add(
        DataAsset(
          package: input.packageName,
          name: '$assetPrefix${artifact.uri.pathSegments.last}',
          file: artifact.uri,
        ),
      );
    }

    output.metadata['emscripten'] = {
      'emcc': result.emcc.uri.toString(),
      'version': result.emcc.version?.toString(),
      'toolchain_file': result.toolchainFile.toString(),
    };
    output.dependencies
      ..addAll(_sourceDependencies())
      ..add(result.emcc.uri)
      ..add(result.toolchainFile);
  }

  /// Builds the module into [outputDirectory] and returns the copied
  /// `.js`/`.wasm` files.
  ///
  /// Use this for Flutter stable, standard `flutter.assets` packaging, or pure
  /// Dart web.
  Future<List<Uri>> runStandalone({
    required Uri outputDirectory,
    Map<String, dynamic>? userDefines,
    Logger? logger,
  }) async {
    final log = logger ?? this.logger;
    final userConfig = UserConfig.parseFromUserDefines(
      targetOS: webOS,
      userDefines: unwrapUserDefines(userDefines, logger: log),
      logger: log,
    );

    final buildDir =
        outDir ?? (buildLocal ? sourceDir.resolve('build/wasm/') : outputDirectory.resolve('cmake/'));
    final result = await _build(buildDir, userConfig, log);
    final artifacts = result.artifacts;

    await Directory.fromUri(outputDirectory).create(recursive: true);
    if (singleFile) {
      // Avoid leaving a stale .wasm behind when switching from the separate
      // output mode to singleFile.
      final staleWasm = File.fromUri(outputDirectory.resolve('$name.wasm'));
      if (await staleWasm.exists()) {
        await staleWasm.delete();
      }
    }
    final copied = <Uri>[];
    for (final artifact in artifacts) {
      final target = outputDirectory.resolve(artifact.uri.pathSegments.last);
      if (artifact.uri != target) {
        await artifact.copy(target.toFilePath());
      }
      copied.add(target);
    }

    log?.info('Emscripten artifacts copied to ${outputDirectory.toFilePath()}');
    return copied;
  }

  Future<({List<File> artifacts, ToolInstance emcc, Uri toolchainFile})> _build(
    Uri buildDir,
    UserConfig userConfig,
    Logger? log,
  ) async {
    await Directory.fromUri(buildDir).create(recursive: true);
    final runner = RunCMakeWasmBuilder(
      name: name,
      sourceDir: sourceDir,
      outDir: buildDir,
      defines: defines,
      linkerFlags: linkerFlags,
      singleFile: singleFile,
      buildMode: buildMode,
      generator: generator,
      targets: targets,
      logLevel: logLevel,
      logger: log,
      userConfig: userConfig,
      emscriptenArgs: emscriptenArgs,
      parallelJobs: parallelJobs,
      parallelUseAllProcessors: parallelUseAllProcessors,
      environment: environment,
    );
    return runner.build();
  }

  static Map<String, dynamic> _parseUserDefines(Object? value, Logger? logger) {
    if (value == null) return const {};
    if (value is Map<String, dynamic>) return unwrapUserDefines(value, logger: logger);
    if (value is Map) return unwrapUserDefines(value.cast<String, dynamic>(), logger: logger);
    logger?.warning('user_defines expected Map, got ${value.runtimeType}; ignored.');
    return const {};
  }

  Iterable<Uri> _sourceDependencies() sync* {
    const sourceExtensions = {
      'c',
      'cc',
      'cpp',
      'cxx',
      'h',
      'hh',
      'hpp',
      'hxx',
      'm',
      'mm',
      'cmake',
      'txt',
      'js',
      'mjs',
    };
    const ignoredDirectories = {
      '.dart_tool',
      '.git',
      '.gradle',
      '.cmake',
      'build',
      'cmake-build',
      'node_modules',
    };
    final directory = Directory.fromUri(sourceDir);
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final baseLength = sourceDir.pathSegments.where((s) => s.isNotEmpty).length;
      final relativeSegments = entity.uri.pathSegments.where((s) => s.isNotEmpty).skip(baseLength);
      if (relativeSegments.any(ignoredDirectories.contains)) continue;
      final extension = entity.path.split('.').last.toLowerCase();
      if (sourceExtensions.contains(extension)) yield entity.uri;
    }
  }
}
