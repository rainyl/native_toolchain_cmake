// ignore_for_file: comment_references
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_assets_cli/data_assets.dart';

import '../builder/linkmode.dart';

/// Searches recursively through the provided [outDir] (or [input.outputDirectory]
/// if [outDir] is null) for native library files that match the expected
/// target filename pattern.
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
///   packageName: 'my_package',
///   names: ['add'],
/// );
/// ```
Future<List<Uri>> addCodeAssets(
  BuildInput input,
  BuildOutputBuilder output, {
  required String packageName,
  required List<String> names,
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
    for (final name in names) {
      final libName = OS.current.libraryFileName(name, linkMode);
      if (entity.path.endsWith(libName)) {
        // this can be more elegant
        logger?.info('Found library file: ${entity.path}');
        output.assets.code.add(
          CodeAsset(
            package: packageName,
            name: '$name.dart',
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

/// **DataAsset not enabled yet by native_assets**
///
/// Searches recursively through [outDir] (or [input.outputDirectory] if [outDir] is null)
/// for files matching the given asset names.
///
/// The [assetNames] are expected to include the full filename with its extension.
/// For each file found whose path ends with one of the provided asset names, a
/// [DataAsset] is added to [output.assets.data] if it has not already been added
/// (tracked via an internal collection of file URIs since [output.assets] is not iterable).
/// The asset is created using [packageName], [assetName] as the asset name,
/// and the discovered file URI.
///
/// Returns a list of URIs corresponding to the added data assets.
///
/// Example:
/// ```dart
/// final foundUris = await addDataAssets(
///   input,
///   output,
///   outDir: myOutputUri,
///   packageName: 'my_package',
///   assetNames: ['lib.js', 'data.json', 'index.html', lib.h],
/// );
/// ```
Future<List<Uri>> addDataAssets(
  BuildInput input,
  BuildOutputBuilder output, {
  required String packageName,
  required List<String> assetNames,
  Uri? outDir,
  Logger? logger,
}) async {
  // TODO: Use output.assets when/if it becomes iterable.
  final List<Uri> foundFiles = [];
  final searchDir = Directory.fromUri(outDir ?? input.outputDirectory);

  logger?.info('Searching for assets in ${searchDir.path}');

  await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
    for (final assetName in assetNames) {
      if (entity is! File) continue;
      final path = entity.path;
      if (path.endsWith(assetName) && !foundFiles.any((uri) => uri.toFilePath() == path)) {
        final uri = Uri.file(path);
        logger?.info('Adding asset file: $uri');
        output.assets.data.add(
          DataAsset(
            package: packageName,
            name: assetName,
            file: uri,
          ),
        );
        foundFiles.add(uri);
      }
    }
  }
  logger?.info('Found assets: $foundFiles');
  return foundFiles;
}

///**DataAsset not enabled yet by native_assets**
///
/// Recursively searches through each directory in [searchDirs].
/// For each file found, a [DataAsset] is then added to [output.assets.data].
///
/// Returns a combined list of URIs corresponding to all the added files.
///
/// Example:
/// ```dart
/// final foundUris = await addDirectories(
///   input,
///   output,
///   [Uri.directory('assets/images/'), Uri.directory('assets/sounds/')],
///   packageName: 'my_package',
/// );
/// ```
Future<List<Uri>> addDirectories(
  BuildInput input,
  BuildOutputBuilder output,
  List<Uri> searchDirs, {
  required String packageName,
  Logger? logger,
}) async {
  final List<Uri> foundFiles = [];

  for (final dirUri in searchDirs) {
    // Create a Directory using the URI.
    final baseDir = Directory.fromUri(dirUri);
    final basePath = dirUri.toFilePath();

    logger?.info('Searching directory: $basePath');

    await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final filePath = entity.path;
      // Ensure the file path starts with the base directory path
      if (!filePath.startsWith(basePath)) {
        continue;
      }
      final relativePath = filePath.substring(basePath.length);
      final fileUri = Uri.file(filePath);
      logger?.info('Adding file: $fileUri with relative path: $relativePath');

      output.assets.data.add(
        DataAsset(
          package: packageName,
          name: relativePath,
          file: fileUri,
        ),
      );
      foundFiles.add(fileUri);
    }
  }

  logger?.info('Found files: $foundFiles');
  return foundFiles;
}
