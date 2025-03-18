// ignore_for_file: comment_references
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:path/path.dart' as p;

import '../builder/linkmode.dart';

extension BuildOutputBuilderCodeAssets on BuildOutputBuilder {
  static final Expando<Set<Uri>> _addedAssets = Expando<Set<Uri>>();

  Set<Uri> get addedAssets => _addedAssets[this] ??= <Uri>{};

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
  Future<List<Uri>> findAndAddCodeAssets(
    BuildInput input, {
    required Map<String, String> names, // key: search library name, value: dart ffi name
    Uri? outDir,
    Logger? logger,
    bool regExp = false,
  }) async {
    final preferredMode = input.config.code.linkModePreference;
    final searchDir = Directory.fromUri(outDir ?? input.outputDirectory);
    final linkMode = getLinkMode(preferredMode);
    final List<Uri> foundFiles = [];
    // Track the added asset names to prevent duplicates even if the file URIs differ.
    final Set<String> addedAssetNames = {};

    logger?.info('Searching for libraries in ${searchDir.path}');
    logger?.info('Preferred link mode: $preferredMode');

    await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      for (final entry in names.entries) {
        final key = entry.key;
        final assetName = entry.value;
        // Skip if we've already added an asset with this name.
        if (addedAssetNames.contains(assetName)) continue;
        final fileName = p.basename(entity.path);
        final found = regExp
            ? RegExp(key).hasMatch(fileName)
            : entity.path.endsWith(OS.current.libraryFileName(key, linkMode));
        if (!found) continue;
        logger?.info('Found library file: ${entity.path}');
        addCodeAsset(
          CodeAsset(
            package: input.packageName,
            name: assetName,
            linkMode: linkMode,
            os: input.config.code.targetOS,
            file: entity.uri,
            architecture: input.config.code.targetArchitecture,
          ),
        );
        foundFiles.add(entity.uri);
        addedAssetNames.add(assetName);
        break; // Only add one file per asset name.
      }
    }
    return foundFiles;
  }

  /// short for [assets.code.add]
  void addCodeAsset(CodeAsset codeAsset) {
    // Only add if we haven't already added this file.
    if (addedAssets.contains(codeAsset.file)) return;
    assets.code.add(codeAsset);
    addedAssets.add(codeAsset.file!);
  }
}
