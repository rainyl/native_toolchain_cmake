// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Prefix of the files and CMake variables this package uses: **D**art
/// **N**ative **T**oolchain **CM**ake.
@visibleForTesting
const dntcmPrefix = 'dntcm';

/// Name of the record `CMakeBuilder.run()` leaves for `CMakeBuilder.runLink()`,
/// one per library ([name]) and build directory.
@visibleForTesting
String cmakeBuildInfoFileNameFor(String name) => '${dntcmPrefix}_build_info_$name.json';

/// Name of the file `CMakeBuilder.runLink()` writes the symbols to keep into,
/// one per library ([libraryName]) and build directory.
///
/// Must match the default of `KEEP_SYMBOLS` in `cmake/treeshake.cmake`.
@visibleForTesting
String cmakeKeepSymbolsFileNameFor(String libraryName) => '${dntcmPrefix}_keep_symbols_$libraryName.txt';

/// Name of the directory in the build directory in which
/// `cmake/treeshake.cmake` stages the tree-shaken libraries and their export
/// files (one file per library).
@visibleForTesting
const cmakeTreeshakeStageDirName = '${dntcmPrefix}_treeshake';

/// Where and how an earlier `CMakeBuilder.run()` built.
///
/// A link hook cannot recompute the build hook's output directory: its own
/// output directory is a different one (the checksums of a build and a link
/// config differ). The build hook therefore records the build directory next to
/// its artifacts, where `CMakeBuilder.runLink()` finds it by walking up from the
/// library it was handed.
///
/// One record per library (`<prefix>_build_info_<name>.json`) and build
/// directory. Build directories are not shared between packages: they live in
/// `hooks_runner/shared/<package>/build/<checksum>/` (or in the package's own
/// `build/` directory with `buildLocal: true`), so the file names never collide
/// across packages.
class CMakeBuildInfo {
  /// The CMake build directory (`cmake -B`), which contains `CMakeCache.txt`.
  final Uri buildDir;

  /// The `CMAKE_INSTALL_PREFIX` the build installed into.
  final Uri installDir;

  /// The `BuildMode` name that was built, e.g. `release`.
  final String buildMode;

  const CMakeBuildInfo({required this.buildDir, required this.installDir, required this.buildMode});

  /// Parses a record, or `null` when [json] is not a well-formed record (a
  /// hand-edited or truncated file must not fail the build).
  static CMakeBuildInfo? tryParse(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final buildDir = json['build_dir'];
    final installDir = json['install_dir'];
    final buildMode = json['build_mode'];
    if (buildDir is! String || installDir is! String || buildMode is! String) return null;
    return CMakeBuildInfo(
      buildDir: Uri.file(buildDir),
      installDir: Uri.file(installDir),
      buildMode: buildMode,
    );
  }

  Map<String, Object?> toJson() => {
    'build_dir': buildDir.toFilePath(),
    'install_dir': installDir.toFilePath(),
    'build_mode': buildMode,
  };

  /// The file `CMakeBuilder.runLink()` writes the keep-list of the library
  /// [libraryName] to (see `cmake/treeshake.cmake`).
  Uri keepSymbolsFileUri(String libraryName) => buildDir.resolve(cmakeKeepSymbolsFileNameFor(libraryName));

  /// The directory in which `dntcm_add_treeshake_target` stages the tree-shaken
  /// libraries and their export files.
  Uri get treeshakeStageDirectory => buildDir.resolve('$cmakeTreeshakeStageDirName/');

  /// Writes the record of the library [name] into [directory].
  Future<File> write({required Uri directory, required String name}) async {
    final file = File.fromUri(directory.resolve(cmakeBuildInfoFileNameFor(name)));
    await file.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
    return file;
  }

  /// Reads the record of the library [name] belonging to [artifact] (e.g. the
  /// library file of a code asset), searching the artifact's directory and up
  /// to [maxDepth] of its parents - a build usually installs to
  /// `<build dir>/install/lib/`.
  ///
  /// Returns `null` when there is no record, or when it describes a different
  /// install prefix than the artifact lives in (a stale record of another
  /// build).
  static Future<CMakeBuildInfo?> read({required Uri artifact, required String name, int maxDepth = 6}) async {
    if (!artifact.isScheme('file')) return null;
    final artifactPath = artifact.toFilePath();
    var directory = File.fromUri(artifact).parent;
    for (var depth = 0; depth <= maxDepth; depth++) {
      for (final file in _recordsIn(directory, name: name)) {
        final Object? json;
        try {
          json = jsonDecode(await file.readAsString());
        } on FormatException {
          continue;
        }
        final info = CMakeBuildInfo.tryParse(json);
        if (info == null) continue;
        if (artifactPath.startsWith(info.installDir.toFilePath())) return info;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    return null;
  }

  /// The record of [name] first, then the records of the other libraries of the
  /// same build directory: one build directory is one configure, so they all
  /// describe the same build directory, install prefix and build mode.
  static Iterable<File> _recordsIn(Directory directory, {required String name}) {
    final exact = File.fromUri(directory.uri.resolve(cmakeBuildInfoFileNameFor(name)));
    final others = <File>[];
    if (directory.existsSync()) {
      for (final entity in directory.listSync()) {
        final baseName = entity.uri.pathSegments.last;
        if (entity is File &&
            baseName.startsWith('${dntcmPrefix}_build_info_') &&
            baseName.endsWith('.json') &&
            entity.path != exact.path) {
          others.add(entity);
        }
      }
    }
    others.sort((a, b) => a.path.compareTo(b.path));
    return [if (exact.existsSync()) exact, ...others];
  }

  @override
  String toString() => 'CMakeBuildInfo(buildDir: $buildDir, installDir: $installDir, buildMode: $buildMode)';
}
