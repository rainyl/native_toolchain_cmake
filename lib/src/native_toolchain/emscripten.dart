// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../builder/builder_args.dart';
import '../builder/user_config.dart';
import '../tool/tool.dart';
import '../tool/tool_instance.dart';
import '../tool/tool_resolver.dart';

const _toolName = 'Emscripten emcc';

/// The oldest Emscripten release supported by `CMakeWasmBuilder`.
///
/// Emscripten 6.0 introduced the `.exe` tool launchers on Windows that
/// [`Emscripten.cmake`] expects, and is the first release series this package
/// is tested against.
final Version minimumEmscriptenVersion = Version(6, 0, 0);

/// Whether [version] is a supported Emscripten version.
bool isSupportedEmscriptenVersion(Version? version) {
  if (version == null) return false;
  // Compare release fields only: Emscripten reports development versions such
  // as `7.0.0-git`, which are semver-pre-release (and therefore compare lower
  // than `7.0.0`). They are still newer than the minimum release.
  final minimum = minimumEmscriptenVersion;
  if (version.major != minimum.major) return version.major > minimum.major;
  if (version.minor != minimum.minor) return version.minor > minimum.minor;
  return version.patch >= minimum.patch;
}

/// The Emscripten compiler driver (`emcc` / `emcc.exe`).
///
/// Discovery order:
///   1. `user_defines.web.emscripten_root` + `emcc`
///   2. `user_defines.web.emsdk_path` + `upstream/emscripten/emcc`
///   3. `PATH`
///   4. `EMSDK` environment variable (only available outside filtered hooks)
///   5. common emsdk installation locations
///   6. system installations (`/usr/bin/emcc`, Homebrew, ...)
///
/// Build hooks run with a filtered environment (no `EMSDK`), so `PATH` or
/// `user_defines` should be used there.
final Tool emcc = Tool(name: _toolName, defaultResolver: _EmccResolver());

class _EmccResolver implements ToolResolver {
  @override
  Future<List<ToolInstance>> resolve({
    required Logger? logger,
    UserConfig? userConfig,
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final executableNames = [
      OS.current.executableFileName('emcc'),
      // Older / unusual installations may only expose the wrapper script.
      'emcc',
    ];

    final candidates = <Uri>[];
    final seen = <String>{};

    void addFile(Uri uri) {
      final normalized = uri.normalizePath();
      if (!seen.add(normalized.toString())) return;
      if (File.fromUri(normalized).existsSync()) {
        candidates.add(normalized);
      }
    }

    void addEmscriptenRoot(String? root) {
      if (root == null || root.isEmpty) return;
      final dir = _normalize(root);
      for (final name in executableNames) {
        addFile(Uri.file('$dir/$name'));
      }
    }

    void addEmsdkRoot(String? root) {
      if (root == null || root.isEmpty) return;
      final dir = _normalize(root);
      for (final name in executableNames) {
        addFile(Uri.file('$dir/upstream/emscripten/$name'));
      }
    }

    // Explicit user configuration wins over everything else.
    addEmscriptenRoot(userConfig?.emscriptenRoot);
    addEmsdkRoot(userConfig?.emsdkPath);

    // PATH is next: activated emsdk installations usually put `emcc` here.
    final pathInstances = await PathToolResolver(
      toolName: _toolName,
      executableName: 'emcc',
    ).resolve(logger: logger, environment: environment);
    for (final instance in pathInstances) {
      addFile(instance.uri);
    }

    addEmsdkRoot(env['EMSDK']);

    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      addEmsdkRoot('$home/emsdk');
    }
    for (final root in const ['/opt/emsdk', '/usr/local/emsdk', 'C:/emsdk']) {
      addEmsdkRoot(root);
    }

    // System installations.
    for (final path in const [
      '/usr/bin/emcc',
      '/usr/local/bin/emcc',
      '/usr/share/emscripten/emcc',
      '/usr/lib/emscripten/emcc',
      '/opt/homebrew/bin/emcc',
      '/opt/homebrew/opt/emscripten/bin/emcc',
    ]) {
      addFile(Uri.file(path));
    }

    if (candidates.isEmpty) {
      logger?.warning(
        'Could not find emcc. Configure user_defines.web.emsdk_path, '
        'add emsdk to PATH, or set EMSDK.',
      );
    } else {
      logger?.fine('Found emcc candidates: $candidates');
    }

    return [
      for (final uri in candidates)
        ToolInstance(
          tool: Tool(name: _toolName),
          uri: uri,
        ),
    ];
  }

  static String _normalize(String path) => path.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
}

/// Resolves the Emscripten installation and its CMake toolchain file.
///
/// Throws with an actionable message when either cannot be found.
Future<({ToolInstance emcc, Uri toolchainFile})> resolveEmscripten({
  UserConfig? userConfig,
  EmscriptenBuilderArgs args = const EmscriptenBuilderArgs(),
  Logger? logger,
  Map<String, String>? environment,
}) async {
  final requestedVersion = args.version ?? userConfig?.emscriptenVersion;
  final candidates = await emcc.defaultResolver!.resolve(
    logger: logger,
    userConfig: userConfig,
    environment: environment,
  );

  // Probe versions individually: one broken candidate (for example an
  // extensionless wrapper that cannot be executed on Windows) must not abort
  // discovery of the remaining installation candidates.
  final instances = <ToolInstance>[];
  for (final candidate in candidates) {
    try {
      instances.add(await CliVersionResolver.lookupVersion(candidate, logger: logger));
    } catch (error) {
      logger?.warning('Skipping emcc candidate ${candidate.uri}: $error');
    }
  }

  final version = requestedVersion == null ? null : Version.parse(requestedVersion);
  if (version != null && !isSupportedEmscriptenVersion(version)) {
    throw ArgumentError(
      'Emscripten $requestedVersion is not supported: version '
      '${minimumEmscriptenVersion.major}.${minimumEmscriptenVersion.minor}+ '
      'is required. Use emsdk 6 or newer.',
    );
  }

  final supported = instances.where((instance) => isSupportedEmscriptenVersion(instance.version)).toList();
  final matching = version == null
      ? supported
      : supported
            .where(
              (instance) =>
                  instance.version != null &&
                  instance.version!.major == version.major &&
                  instance.version!.minor == version.minor &&
                  instance.version!.patch == version.patch,
            )
            .toList();
  if (matching.isEmpty) {
    final found = instances.map((e) => '${e.uri} (version ${e.version ?? 'unknown'})').join(', ');
    throw Exception(
      'Failed to find supported Emscripten ${requestedVersion ?? ''} (emcc). '
      'Emscripten ${minimumEmscriptenVersion.major}.${minimumEmscriptenVersion.minor}+ is required. '
      'Found: ${found.isEmpty ? 'none' : found}. '
      'Configure user_defines.web.emsdk_path or add emsdk to PATH.',
    );
  }

  final instance = matching.first;
  final toolchainFile = await findEmscriptenToolchainFile(
    emccInstance: instance,
    userConfig: userConfig,
    args: args,
    logger: logger,
  );

  return (emcc: instance, toolchainFile: toolchainFile);
}

/// Finds `Emscripten.cmake` for the given [emccInstance].
Future<Uri> findEmscriptenToolchainFile({
  required ToolInstance emccInstance,
  UserConfig? userConfig,
  EmscriptenBuilderArgs args = const EmscriptenBuilderArgs(),
  Logger? logger,
}) async {
  final candidates = <Uri>[];
  final tried = <String>{};

  void addCandidate(String? path) {
    if (path == null || path.isEmpty) return;
    final file = File(path.replaceAll(r'\', '/'));
    if (!file.existsSync()) return;
    final uri = file.absolute.uri;
    if (!tried.add(uri.toString())) return;
    candidates.add(uri);
  }

  void addEmscriptenRoot(String? root) {
    if (root == null || root.isEmpty) return;
    final dir = root.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
    addCandidate('$dir/cmake/Modules/Platform/Emscripten.cmake');
  }

  void addEmsdkRoot(String? root) {
    if (root == null || root.isEmpty) return;
    final dir = root.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
    addCandidate('$dir/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake');
  }

  // 1. Explicit configuration.
  addCandidate(args.toolchainFile);
  addCandidate(userConfig?.emscriptenToolchainFile);

  // 2. Explicit roots.
  addEmscriptenRoot(args.emscriptenRoot ?? userConfig?.emscriptenRoot);
  addEmsdkRoot(args.emsdkPath ?? userConfig?.emsdkPath);

  // 3. Derive from the emcc binary (works for emsdk and system
  // installations). Use the path as discovered first: resolving symlinks can
  // change the Emscripten root (e.g. package-manager junction layouts where
  // the config file next to the shim differs from the one next to the real
  // binary).
  void addFromEmccDir(String emccDir) {
    addCandidate('$emccDir/cmake/Modules/Platform/Emscripten.cmake');
    addCandidate('$emccDir/../lib/emscripten/cmake/Modules/Platform/Emscripten.cmake');
    addCandidate('$emccDir/../share/emscripten/cmake/Modules/Platform/Emscripten.cmake');
    addCandidate('$emccDir/../libexec/emscripten/cmake/Modules/Platform/Emscripten.cmake');
    // Homebrew installs the whole Emscripten tree into `libexec`, and `bin/emcc`
    // is a wrapper script that execs `libexec/emcc` (not a symlink, so symlink
    // resolution cannot reach the real root either).
    addCandidate('$emccDir/../libexec/cmake/Modules/Platform/Emscripten.cmake');
  }

  addFromEmccDir(File.fromUri(emccInstance.uri).parent.path);
  try {
    final resolved = await File.fromUri(emccInstance.uri).resolveSymbolicLinks();
    addFromEmccDir(File(resolved).parent.path);
  } on FileSystemException {
    // No symlink information available; the original path is enough.
  }

  // 4. Known system layouts.
  for (final path in const [
    '/usr/share/emscripten/cmake/Modules/Platform/Emscripten.cmake',
    '/usr/lib/emscripten/cmake/Modules/Platform/Emscripten.cmake',
    '/usr/local/share/emscripten/cmake/Modules/Platform/Emscripten.cmake',
    '/opt/homebrew/share/emscripten/cmake/Modules/Platform/Emscripten.cmake',
    '/opt/homebrew/opt/emscripten/libexec/emscripten/cmake/Modules/Platform/Emscripten.cmake',
    '/opt/homebrew/opt/emscripten/libexec/cmake/Modules/Platform/Emscripten.cmake',
    '/usr/local/opt/emscripten/libexec/emscripten/cmake/Modules/Platform/Emscripten.cmake',
    '/usr/local/opt/emscripten/libexec/cmake/Modules/Platform/Emscripten.cmake',
  ]) {
    addCandidate(path);
  }

  if (candidates.isEmpty) {
    throw Exception(
      'Failed to locate Emscripten.cmake for $emccInstance. '
      'Configure user_defines.web.emscripten_toolchain_file '
      '(or web.emscripten_root / web.emsdk_path).',
    );
  }

  logger?.fine('Using Emscripten toolchain file: ${candidates.first}');
  return candidates.first;
}
