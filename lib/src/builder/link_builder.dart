// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import 'build_info.dart';
import 'builder.dart';
import 'linkmode.dart';

/// The link-hook half of [CMakeBuilder].
///
/// The build hook compiles and records where it built (`CMakeBuildInfo`); this
/// extension links the final library in `hook/link.dart` with only the native
/// symbols the compiled Dart code uses, which is the only hook that knows them.
extension CMakeLinkBuilder on CMakeBuilder {
  /// Links the tree-shaken library in a link hook.
  ///
  /// This is the counterpart of `CMakeBuilder.run()`: the build hook compiles
  /// (and, when tree shaking, calls `dntcm_add_treeshake_target` from
  /// `cmake/treeshake.cmake`), the link hook knows which `@ffi.Native` functions
  /// the program uses (`symbolsFromRecordedUses()`, or a keep-list of your own)
  /// and links the final library with only those symbols. Doing that in the
  /// build hook is not possible: the recorded usages only exist in the link
  /// hook's input, and a keep-list from an earlier build strips symbols the
  /// current code needs.
  ///
  /// Needs the build info of `CMakeBuilder.run()` (written next to its
  /// artifacts, found by walking up from the files in [LinkInput.assets]) and a
  /// `dntcm_add_treeshake_target(NAME: name)` in the CMake project.
  ///
  /// On success the tree-shaken library is copied into
  /// [LinkInput.outputDirectory] and registered as the code asset [assetName].
  ///
  /// Returns `false`, after logging why, when the build info, the keep-list or
  /// the staged library is missing, or when the configuration does not want a
  /// dynamic library; throws when the CMake build fails. Callers that must not
  /// fail a build should fall back to the build hook's library.
  ///
  /// - [assetName]: code asset id to register, e.g. `mylib.dart`.
  /// - [libraryName]: base name of the library, defaults to [CMakeBuilder.name].
  /// - [treeshakeTarget]: CMake target to build, defaults to `<name>_treeshake`.
  /// - [symbolsToKeep]: the keep-list; nothing is linked when it is empty.
  /// - [buildInfo]: skips the lookup in [LinkInput.assets].
  Future<bool> runLink({
    required LinkInput input,
    required LinkOutputBuilder output,
    required String assetName,
    Iterable<String>? symbolsToKeep,
    String? libraryName,
    String? treeshakeTarget,
    CMakeBuildInfo? buildInfo,
    Logger? logger,
  }) async {
    logger ??= this.logger;
    if (!input.config.buildCodeAssets) {
      logger?.info('No code assets requested (buildCodeAssets=false); skipping the link.');
      return false;
    }
    final code = input.config.code;
    if (getLinkMode(code.linkModePreference) != DynamicLoadingBundled()) {
      logger?.warning(
        'Linking a tree-shaken library needs a dynamic library, but the configuration prefers '
        '${code.linkModePreference}; bundle the build hook library instead.',
      );
      return false;
    }
    final baseName = libraryName ?? name;
    final target = treeshakeTarget ?? '${name}_treeshake';

    final symbols = <String>{
      for (final symbol in symbolsToKeep ?? const <String>[])
        if (symbol.trim().isNotEmpty) symbol.trim(),
    };
    if (symbols.isEmpty) {
      logger?.warning('No native symbol to keep; not linking a tree-shaken library.');
      return false;
    }

    var info = buildInfo;
    if (info == null) {
      for (final asset in input.assets.code) {
        final file = asset.file;
        if (file == null) continue;
        info = await CMakeBuildInfo.read(artifact: file, name: name);
        if (info != null) break;
      }
    }
    if (info == null) {
      logger?.warning(
        'No CMake build info next to the assets of ${input.packageName}; '
        'was the library built with CMakeBuilder.run()?',
      );
      return false;
    }
    logger?.fine('Linking $target in ${info.buildDir} (${info.buildMode})');

    // The keep-list is what `cmake/treeshake.cmake` reads at build time; writing
    // it changes nothing else, so only the export file is regenerated and the
    // library is relinked. It is not declared as an output dependency: this hook
    // writes it itself, and the output timestamp predates that write.
    final symbolsFile = File.fromUri(info.keepSymbolsFileUri(baseName));
    await symbolsFile.create(recursive: true);
    await symbolsFile.writeAsString('${(symbols.toList()..sort()).join('\n')}\n');

    final task = await createTask(
      outDir: info.buildDir,
      targetOS: code.targetOS,
      targetArchitecture: code.targetArchitecture,
      buildModeName: info.buildMode,
      android: code.targetOS == OS.android ? code.android : null,
      iOS: code.targetOS == OS.iOS ? code.iOS : null,
      macOS: code.targetOS == OS.macOS ? code.macOS : null,
      targets: [target],
      userDefines: input.json['user_defines'] as Map<String, dynamic>? ?? const {},
      input: input,
      packageRoot: input.packageRoot,
      logger: logger,
    );
    await task.buildTarget(
      targets: [target],
      environment: await buildEnvironment(
        targetOS: code.targetOS,
        targetArchitecture: code.targetArchitecture,
        logger: logger,
      ),
    );

    final staged = File.fromUri(
      info.treeshakeStageDirectory.resolve(code.targetOS.libraryFileName(baseName, DynamicLoadingBundled())),
    );
    if (!staged.existsSync()) {
      logger?.warning(
        'The tree-shaken library ${staged.path} does not exist. Does the CMake project call '
        'dntcm_add_treeshake_target(NAME: $name) (see cmake/treeshake.cmake)?',
      );
      return false;
    }
    final linked = File.fromUri(
      input.outputDirectory.resolve(code.targetOS.libraryFileName(baseName, DynamicLoadingBundled())),
    );
    await linked.parent.create(recursive: true);
    await staged.copy(linked.path);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: assetName,
        linkMode: DynamicLoadingBundled(),
        file: linked.uri,
      ),
    );
    logger?.info(
      'Linked ${linked.path} with ${symbols.length} of the recorded native symbols '
      '(${staged.lengthSync()} bytes).',
    );
    return true;
  }
}
