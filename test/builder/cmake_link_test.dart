// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

@OnPlatform({'mac-os': Timeout.factor(2), 'windows': Timeout.factor(10)})
import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'treeshake_test';

/// The libraries of `testfiles/treeshake`, both built in the same build directory.
const _withUsedFunction = 'treeshake_test';
const _withUsedFunction2 = 'treeshake_test2';
const _libraries = [_withUsedFunction, _withUsedFunction2];

void main() {
  test('CMakeBuilder.runLink links the tree-shaken library', () async {
    final fixture = await _buildFixture();
    final result = await fixture.link(_withUsedFunction, symbolsToKeep: ['used_function']);
    expect(result.linked, isTrue);

    final linkedFile = result.linkedFile!;
    expect(linkedFile.parent.uri.normalizePath(), result.outputDirectory.normalizePath());
    expect(
      linkedFile.lengthSync(),
      lessThan(fixture.unrestricted(_withUsedFunction).lengthSync()),
      reason: 'dropping the unused function also drops the blob it references',
    );

    // Loading it proves the exports are complete: only the kept symbol resolves.
    final library = openDynamicLibraryForTest(linkedFile.path);
    expect(library.lookup<NativeFunction<Int32 Function()>>('used_function'), isNotNull);
    expect(
      () => library.lookup<NativeFunction<Int32 Function()>>('unused_function'),
      throwsA(isA<ArgumentError>()),
      reason: 'the unused function is tree-shaken away',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('CMakeBuilder.runLink keeps one keep-list per library', () async {
    final fixture = await _buildFixture();
    const symbols = {_withUsedFunction: 'used_function', _withUsedFunction2: 'used_function2'};

    for (final MapEntry(key: library, value: keep) in symbols.entries) {
      final result = await fixture.link(library, symbolsToKeep: [keep]);
      expect(result.linked, isTrue, reason: 'linking $library');
      final dynamicLibrary = openDynamicLibraryForTest(result.linkedFile!.path);
      expect(dynamicLibrary.lookup<NativeFunction<Int32 Function()>>(keep), isNotNull);
      final other = symbols.entries.firstWhere((e) => e.key != library).value;
      expect(
        () => dynamicLibrary.lookup<NativeFunction<Int32 Function()>>(other),
        throwsA(isA<ArgumentError>()),
        reason: '$library must not export the symbol of the other library',
      );
    }

    // One keep-list per library, not one file the second link overwrites.
    final keepFiles = Directory.fromUri(fixture.buildInput.outputDirectory)
        .listSync()
        .whereType<File>()
        .where((file) => file.uri.pathSegments.last.startsWith('dntcm_keep_symbols_'))
        .toList();
    expect(keepFiles, hasLength(_libraries.length));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('CMakeBuilder.runLink without symbols does not link', () async {
    final fixture = await _buildFixture();
    final result = await fixture.link(_withUsedFunction, symbolsToKeep: const []);
    expect(result.linked, isFalse);
    expect(result.assets, isEmpty);
  });

  test('CMakeBuilder.runLink without build info does not link', () async {
    final fixture = await _buildFixture();
    final result = await fixture.link(_withUsedFunction, symbolsToKeep: const ['used_function'], assets: []);
    expect(result.linked, isFalse);
    expect(result.assets, isEmpty);
  });

  test('CMakeBuilder.runLink does not link when nothing is staged', () async {
    final fixture = await _buildFixture();
    // An existing target that is not a dntcm_add_treeshake_target: it builds,
    // but stages no library for runLink to pick up.
    final result = await fixture.link(
      _withUsedFunction,
      symbolsToKeep: const ['used_function'],
      treeshakeTarget: _withUsedFunction,
    );
    expect(result.linked, isFalse);
    expect(result.assets, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('CMakeBuilder.runLink throws when the CMake build fails', () async {
    final fixture = await _buildFixture();
    await expectLater(
      fixture.link(
        _withUsedFunction,
        symbolsToKeep: const ['used_function'],
        treeshakeTarget: 'does_not_exist_treeshake',
      ),
      throwsA(isA<Exception>()),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('CMakeBuilder.runLink does not link a static configuration', () async {
    final fixture = await _buildFixture();
    final result = await fixture.link(
      _withUsedFunction,
      symbolsToKeep: const ['used_function'],
      linkModePreference: LinkModePreference.static,
    );
    expect(result.linked, isFalse);
    expect(result.assets, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('CMakeBuilder.forLink cannot run()', () async {
    final packageRoot = await tempDirForTest();
    final buildInput = BuildInput(
      (BuildInputBuilder()
            ..setupShared(
              packageName: _package,
              packageRoot: packageRoot,
              outputFile: packageRoot.resolve('output.json'),
              outputDirectoryShared: await tempDirForTest(),
            )
            ..config.setupBuild(linkingEnabled: false))
          .json,
    );
    await expectLater(
      CMakeBuilder.forLink(
        name: _withUsedFunction,
      ).run(input: buildInput, output: BuildOutputBuilder(), logger: logger),
      throwsA(isA<StateError>()),
    );
  });
}

/// The outcome of one `runLink` call.
class _LinkResult {
  final bool linked;
  final LinkOutputBuilder output;
  final Uri outputDirectoryUri;

  _LinkResult(this.linked, this.output, this.outputDirectoryUri);

  List<CodeAsset> get assets => LinkOutput(output.json).assets.code;
  File? get linkedFile => assets.isEmpty ? null : File.fromUri(assets.single.file!);
  Uri get outputDirectory => outputDirectoryUri;
}

/// A build hook run of `testfiles/treeshake` (two libraries, one build directory).
class _Fixture {
  final BuildInput buildInput;

  _Fixture(this.buildInput);

  File unrestricted(String library) =>
      File.fromUri(buildInput.outputDirectory.resolve('install/lib/').resolve(_fileName(library)));

  /// Runs the link hook for [library] the way `hook/link.dart` would: the build
  /// hook's library is handed over through `input.assets`.
  Future<_LinkResult> link(
    String library, {
    required List<String> symbolsToKeep,
    String? treeshakeTarget,
    LinkModePreference linkModePreference = LinkModePreference.dynamic,
    List<EncodedAsset>? assets,
  }) async {
    final handover = CodeAsset(
      package: _package,
      name: '$library.dart',
      linkMode: DynamicLoadingBundled(),
      file: unrestricted(library).uri,
    );
    final input = LinkInput(
      (LinkInputBuilder()
            ..setupShared(
              packageName: _package,
              packageRoot: buildInput.packageRoot,
              outputFile: buildInput.packageRoot.resolve('${library}_link_input.json'),
              outputDirectoryShared: buildInput.outputDirectoryShared,
            )
            ..setupLink(
              assets: assets ?? [handover.encode()],
              assetsFromLinking: const [],
              recordedUsesFile: null,
            )
            ..addExtension(
              CodeAssetExtension(
                targetOS: OS.current,
                macOS: OS.current == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null,
                targetArchitecture: Architecture.current,
                linkModePreference: linkModePreference,
                cCompiler: cCompiler,
              ),
            ))
          .json,
    );
    final output = LinkOutputBuilder();
    final linked = await CMakeBuilder.forLink(name: library).runLink(
      input: input,
      output: output,
      assetName: '$library.dart',
      symbolsToKeep: symbolsToKeep,
      treeshakeTarget: treeshakeTarget,
      logger: logger,
    );
    return _LinkResult(linked, output, input.outputDirectory);
  }
}

String _fileName(String library) => OS.current.libraryFileName(library, DynamicLoadingBundled());

Future<_Fixture> _buildFixture() async {
  final packageRoot = await tempDirForTest();
  final sharedUri = await tempDirForTest();
  final buildInput = BuildInput(
    (BuildInputBuilder()
          ..setupShared(
            packageName: _package,
            packageRoot: packageRoot,
            outputFile: packageRoot.resolve('build_output.json'),
            outputDirectoryShared: sharedUri,
          )
          ..config.setupBuild(linkingEnabled: true)
          ..addExtension(
            CodeAssetExtension(
              targetOS: OS.current,
              macOS: OS.current == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null,
              targetArchitecture: Architecture.current,
              linkModePreference: LinkModePreference.dynamic,
              cCompiler: cCompiler,
            ),
          ))
        .json,
  );
  await CMakeBuilder.create(
    name: _withUsedFunction,
    sourceDir: Directory('test/builder/testfiles/treeshake').absolute.uri,
    targets: ['install'],
    defines: {'CMAKE_INSTALL_PREFIX': buildInput.outputDirectory.resolve('install/').toFilePath()},
    logger: logger,
  ).run(input: buildInput, output: BuildOutputBuilder(), logger: logger);
  return _Fixture(buildInput);
}
