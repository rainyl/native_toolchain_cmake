// ignore_for_file: comment_references
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_assets_cli/data_assets.dart';

import '../builder/linkmode.dart';

/// Library names must be without prefix and extensions.
/// Searches recursively through the provided [outDir] (or [input.outputDirectory]
/// if [outDir] is null) for native library files that match the given [names]
/// and adds them to [output.assets.code].
///
/// [names] is used to map a found library file to a foreign function interface
/// in Dart. For example, foo_windows_x64.dll needing to map to the native_foo
/// FFI interface would map {'foo_windows_x64': 'native_foo.dart'}.
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
///   names: ['add'],
/// );
/// ```
Future<List<Uri>> addFoundCodeAssets(
  BuildInput input,
  BuildOutputBuilder output, {
  required Map<String, String> names, // key: search library name, value: dart ffi name
  Uri? outDir,
  Logger? logger,
}) async {
  final preferredMode = input.config.code.linkModePreference;
  final searchDir = Directory.fromUri(outDir ?? input.outputDirectory);
  final linkMode = getLinkMode(preferredMode);
  final List<Uri> foundFiles = [];

  logger?.info('Searching for libraries in ${searchDir.path}');
  logger?.info('Preferred link mode: $preferredMode');

  await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    for (final entry in names.entries) {
      final searchKey = entry.key;
      final assetFilename = entry.value;
      final libName = OS.current.libraryFileName(searchKey, linkMode);
      if (entity.path.endsWith(libName)) {
        logger?.info('Found library file: ${entity.path}');
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: assetFilename,
            linkMode: linkMode,
            os: input.config.code.targetOS,
            file: entity.uri,
            architecture: input.config.code.targetArchitecture,
          ),
        );
        foundFiles.add(entity.uri);
        break;
      }
    }
  }
  return foundFiles;
}
