// ignore_for_file: comment_references
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_assets_cli/data_assets.dart';

/// Searches recursively through [outDir] (or [input.outputDirectory] if [outDir]
/// is null) for library files matching the given [dynLibNames] and [staticLibNames].
///
/// For each file found that matches the expected filename (as determined by
/// [input.config.code.targetOS.libraryFileName]), a [CodeAsset] is added to
/// [output.assets.code] if it has not been added already (tracked via an internal set
/// of file paths). The candidate file name is computed using a concrete [LinkMode]
/// based on the link mode preference, as follows:
///
///   - If [input.config.code.linkModePreference] implements [DynamicLoading],
///     then [DynamicLoadingBundled] will be used and only libraries from
///     [dynLibNames] are searched.
///   - If [input.config.code.linkModePreference] implements [StaticLinking],
///     then [StaticLinking] will be used and only libraries from [staticLibNames]
///     are searched.
///
/// Returns a list of URIs corresponding to the added code assets.
///
/// See also:
///   - [CodeAsset], which represents the native code asset.
///   - [BuildInput] and [BuildOutputBuilder] for context on asset building.
///
/// Example:
/// ```dart
/// final foundUris = await addLibraries(
///   input,
///   output,
///   outDir: myOutputUri,
///   packageName: 'my_package',
///   staticLibNames: ['mylib_static'],
///   dynLibNames: ['mylib_dynamic'],
/// );
/// ```
Future<List<Uri>> addLibraries(
  BuildInput input,
  BuildOutputBuilder output,
  Uri? outDir, {
  required String packageName,
  required List<String> staticLibNames,
  required List<String> dynLibNames,
  Logger? logger,
}) async {
  final preferredMode = input.config.code.linkModePreference;
  final directory = outDir ?? input.outputDirectory;
  final List<Uri> foundFiles = [];

  final searchDir = Directory(directory.toFilePath());

  logger?.info('Searching for libraries in ${searchDir.path}');
  logger?.info('Preferred link mode: $preferredMode');

  // Map the link mode preference by LinkModePreference.name
  LinkMode linkMode;
  List<String> libNames;
  if (preferredMode.name == 'dynamic') {
    logger?.info('Using dynamic link mode');
    linkMode = DynamicLoadingBundled();
    libNames = dynLibNames;
  } else if (preferredMode.name == 'static') {
    logger?.info('Using static link mode');
    linkMode = StaticLinking();
    libNames = staticLibNames;
  } else {
    throw UnsupportedError('Unsupported link mode preference: $preferredMode');
  }

  for (final libName in libNames) {
    final fileName = input.config.code.targetOS.libraryFileName(libName, linkMode);
    await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final path = entity.path;
        if (path.endsWith(fileName) && !foundFiles.any((uri) => uri.toFilePath() == path)) {
          final uri = Uri.file(path);
          logger?.info('Adding library as Code Asset: $uri');
          output.assets.code.add(
            CodeAsset(
              package: packageName,
              name: "$libName.dart",
              linkMode: linkMode,
              os: input.config.code.targetOS,
              file: uri,
              architecture: input.config.code.targetArchitecture,
            ),
          );
          foundFiles.add(uri);
        }
      }
    }
  }
  logger?.info('Found libraries: $foundFiles');
  return foundFiles;
}

/// ** DataAsset not enabled yet by native_assets**
/// Searches recursively through [outDir] (or [input.outputDirectory] if [outDir] is null)
/// for files matching the given asset names.
///
/// The [assetNames] are expected to include the full filename with its extension.
/// For each file found whose path ends with one of the provided asset names, a
/// [DataAsset] is added to [output.assets.data] if it has not already been added
/// (tracked via an internal collection of file URIs). The asset is created using
/// [packageName], [assetName] as the asset name, and the discovered file URI.
///
/// Returns a list of URIs corresponding to the added data assets.
///
/// Example:
/// ```dart
/// final foundUris = await addAssets(
///   input,
///   output,
///   outDir: myOutputUri,
///   packageName: 'my_package',
///   assetNames: ['lib.js', 'data.json', 'lib.h'],
/// );
/// ```
Future<List<Uri>> addAssets(
  BuildInput input,
  BuildOutputBuilder output,
  Uri? outDir, {
  required String packageName,
  required List<String> assetNames,
  Logger? logger,
}) async {
  final directory = outDir ?? input.outputDirectory;
  final List<Uri> foundFiles = [];
  final searchDir = Directory(directory.toFilePath());

  logger?.info('Searching for assets in ${searchDir.path}');

  for (final assetName in assetNames) {
    await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
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
  }
  logger?.info('Found assets: $foundFiles');
  return foundFiles;
}

///** DataAsset not enabled yet by native_assets**
/// Recursively searches through each directory in [searchDirs].
/// For each file found, the relative path is computed by removing the base directory’s
/// path from the file’s full path. A [DataAsset] is then added to [output.assets.data].
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
    final basePath =
        baseDir.path.endsWith(Platform.pathSeparator) ? baseDir.path : baseDir.path + Platform.pathSeparator;

    logger?.info('Searching directory: $basePath');

    await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
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
  }

  logger?.info('Found files: $foundFiles');
  return foundFiles;
}
