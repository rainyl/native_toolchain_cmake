// ignore_for_file: comment_references
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:path/path.dart' as p;

import '../builder/linkmode.dart';

/// Searches recursively through the provided [outDir] (or [input.outputDirectory]
/// if not provided) for native library files that match the given [names]
/// and adds them to [output.assets.code].
///
/// [names] are used to map a found library file to package URI.
/// e.g., for `foo_windows_x64.dll` -> `package:my_pkg/native_foo.dart`,
/// should provide `{'foo_windows_x64': 'native_foo.dart'}`.
///
/// If [regExp] is true, keys in [names] are treated as regular expression patterns to match library filenames.
/// Use regExp if the built libraries are something like `libadd-1.dll`.
/// e.g.,
/// ```dart
/// {r'(lib)?add-\d\.(dll|so|dylib)': 'native_foo.dart'}.
/// ```
///
/// The expected filename is computed using the current operating system's naming conventions
/// combined with a concrete [LinkMode] derived from [input.config.code.linkModePreference].
/// For each file that ends with the computed library filename for one of the provided [names],
/// a [CodeAsset] is created and added to [output.assets.code] if it hasn't already been added.
///
/// Duplicate assets are avoided by tracking previously added file paths internally
/// as [output.assets] is not iterable.
///
/// Returns a list of URIs corresponding to all the added code assets.
///
/// Example:
/// ```dart
/// final foundUris = await addCodeAssets(
///   input,
///   output,
///   outDir: myOutputUri,
///   names: {'add': 'add.dart'},
/// );
/// ```
///
/// ```dart
/// final foundUris = await addCodeAssets(
///   input,
///   output,
///   outDir: myOutputUri,
///   names: { r'(lib)?add\.(dll|so|dylib)': 'add.dart' },
///   regExp=true,
/// );
/// ```
Future<List<Uri>> addFoundCodeAssets(
  BuildInput input,
  BuildOutputBuilder output, {
  required Map<String, String> names, // key: search library name, value: dart ffi name
  Uri? outDir,
  Logger? logger,
  bool regExp = false,
}) async {
  final preferredMode = input.config.code.linkModePreference;
  final searchDir = Directory.fromUri(outDir ?? input.outputDirectory);
  final linkMode = getLinkMode(preferredMode);
  final List<Uri> foundFiles = [];

  logger?.info('Searching for libraries in ${searchDir.path}');
  logger?.info('Preferred link mode: $preferredMode');

  await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    for (final MapEntry(:key, value: name) in names.entries) {
      // even on windows, library name may be `libadd.dll` instead of `add.dll` sometimes,
      // e.g., when using mingw64, so allow using RegExp matching if regExp=true.
      final found = regExp
          ? RegExp(key).hasMatch(p.basename(entity.path))
          : entity.path.endsWith(OS.current.libraryFileName(key, linkMode));
      if (!found) continue;
      logger?.info('Found library file: ${entity.path}');
      output.addCodeAsset(
        CodeAsset(
          package: input.packageName,
          name: name,
          linkMode: linkMode,
          os: input.config.code.targetOS,
          file: entity.uri,
          architecture: input.config.code.targetArchitecture,
        ),
      );
      foundFiles.add(entity.uri);
      break; // only add one file per name
    }
  }
  return foundFiles;
}

extension BuildOutputBuilderCodeAssets on BuildOutputBuilder {
  /// short for [assets.code.add]
  void addCodeAsset(CodeAsset codeAsset) {
    assets.code.add(codeAsset);
  }

  /// extension method for [addFoundCodeAssets]
  Future<List<Uri>> findAndAddCodeAssets(
    BuildInput input, {
    required Map<String, String> names,
    Uri? outDir,
    Logger? logger,
    bool regExp = false,
  }) async =>
      addFoundCodeAssets(input, this, names: names, outDir: outDir, logger: logger, regExp: regExp);
}
