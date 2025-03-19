// ignore_for_file: comment_references
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:path/path.dart' as p;

import '../builder/linkmode.dart';

extension BuildOutputBuilderCodeAssets on BuildOutputBuilder {
  static final Expando<Set<String>> _addedAssetIds = Expando<Set<String>>();

  Set<String> get addedAssetIds => _addedAssetIds[this] ??= <String>{};

  /// Searches recursively through the provided [outDir] (or [input.outputDirectory]
  /// if not provided) for native library files that match the given [names]
  /// and adds them to [assets.code].
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
  /// a [CodeAsset] is created and added to [assets.code] if it hasn't already been added.
  ///
  /// Duplicate assets are avoided by tracking previously added file paths internally
  /// as [assets] is not iterable.
  ///
  /// Returns a list of the added code assets.
  ///
  /// Example:
  /// ```dart
  /// final added = await output.findAndAddCodeAssets(
  ///   input,
  ///   output,
  ///   outDir: myOutputUri,
  ///   names: {'add': 'add.dart'},
  /// );
  /// ```
  ///
  /// ```dart
  /// final added = await output.findAndAddCodeAssets(
  ///   input,
  ///   output,
  ///   outDir: myOutputUri,
  ///   names: { r'(lib)?add\.(dll|so|dylib)': 'add.dart' },
  ///   regExp=true,
  /// );
  /// ```
  Future<List<CodeAsset>> findAndAddCodeAssets(
    BuildInput input, {
    required Map<String, String> names, // key: search library name, value: dart ffi name
    Uri? outDir,
    Logger? logger,
    bool regExp = false,
  }) async {
    final foundAssets = await findCodeAssets(
      input,
      names: names,
      outDir: outDir,
      logger: logger,
      regExp: regExp,
    );
    final addedAssets = addAllCodeAssets(foundAssets, logger: logger);
    return addedAssets;
  }

  /// Finds native library files in the provided [outDir] (or [input.outputDirectory] if not provided)
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
  /// returns a list of the found code assets.
  Future<Set<CodeAsset>> findCodeAssets(
    BuildInput input, {
    required Map<String, String> names, // key: search library name, value: dart ffi name
    Uri? outDir,
    Logger? logger,
    bool regExp = false,
  }) async {
    final preferredMode = input.config.code.linkModePreference;
    final searchDir = Directory.fromUri(outDir ?? input.outputDirectory);
    final linkMode = getLinkMode(preferredMode);
    final Set<CodeAsset> foundAssets = {};

    logger?.info('Searching for libraries in ${searchDir.path}');
    logger?.info('Preferred link mode: $preferredMode');

    await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      for (final MapEntry(:key, value: assetName) in names.entries) {
        final found = regExp
            ? RegExp(key).hasMatch(p.basename(entity.path))
            : entity.path.endsWith(OS.current.libraryFileName(key, linkMode));
        if (!found) continue;
        logger?.info('Found library file: ${entity.path}');
        final asset = CodeAsset(
          package: input.packageName,
          name: assetName,
          linkMode: linkMode,
          os: input.config.code.targetOS,
          file: entity.uri,
          architecture: input.config.code.targetArchitecture,
        );
        foundAssets.add(asset);
        break; // Only add one file per asset name.
      }
    }
    return foundAssets;
  }

  /// short for [assets.code.add]
  bool addCodeAsset(CodeAsset codeAsset) {
    // Only add if we haven't already added this file.
    if (addedAssetIds.contains(codeAsset.id)) return false;
    assets.code.add(codeAsset);
    addedAssetIds.add(codeAsset.id);
    return true;
  }

  /// add all code assets, won't add if already added
  List<CodeAsset> addAllCodeAssets(Iterable<CodeAsset> codeAssets, {Logger? logger}) {
    final addedAssets = <CodeAsset>[];
    for (final asset in codeAssets) {
      logger?.info('Adding asset: $asset');
      if (!addedAssetIds.contains(asset.id)) {
        addCodeAsset(asset);
        addedAssets.add(asset);
      }
    }
    return addedAssets;
  }
}
