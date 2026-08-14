// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
//
// This file is adapted from https://github.com/dart-lang/native/tree/main/pkgs/native_toolchain_c
// Copyright (c) 2024, the Dart project authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The SDK / NDK root discovery order is aligned with the Flutter tool's
// `AndroidSdk.locateAndroidSdk()` and `AndroidSdk.getNdkDirectoriesInResolutionOrder()`
// (see https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/android/android_sdk.dart).

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../builder/user_config.dart';
import '../tool/tool.dart';
import '../tool/tool_instance.dart';
import '../tool/tool_resolver.dart';
import '../utils/run_process.dart';
import 'clang.dart';

final androidNdk = Tool(name: 'Android NDK', defaultResolver: _AndroidNdkResolver());

/// [clang] with [Tool.defaultResolver] for the [OS.android] NDK.
final androidNdkClang = Tool(name: clang.name, defaultResolver: _AndroidNdkResolver());

/// [llvmAr] with [Tool.defaultResolver] for the [OS.android] NDK.
final androidNdkLlvmAr = Tool(name: llvmAr.name, defaultResolver: _AndroidNdkResolver());

/// [lld] with [Tool.defaultResolver] for the [OS.android] NDK.
final androidNdkLld = Tool(name: lld.name, defaultResolver: _AndroidNdkResolver());

/// Environment variable documented at
/// https://developer.android.com/studio/command-line/variables.html#envar
const kAndroidHome = 'ANDROID_HOME';

/// No official environment variable for the NDK root is documented:
/// https://developer.android.com/tools/variables#envar
/// The following three are the most commonly used.
const kAndroidNdkHome = 'ANDROID_NDK_HOME';
const kAndroidNdkPath = 'ANDROID_NDK_PATH';
const kAndroidNdkRoot = 'ANDROID_NDK_ROOT';

/// Host directory name under `<ndk>/toolchains/llvm/prebuilt/` for each
/// supported host OS.
///
/// From https://developer.android.com/ndk/guides/other_build_systems.
const _llvmHostDirectoryName = <String, String>{
  'macos': 'darwin-x86_64',
  'linux': 'linux-x86_64',
  'windows': 'windows-x86_64',
};

class _AndroidNdkResolver implements ToolResolver {
  @override
  Future<List<ToolInstance>> resolve({
    required Logger? logger,
    UserConfig? userConfig,
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;

    final sdkRoots = await _collectSdkRootCandidates(
      environment: env,
      userConfig: userConfig,
      logger: logger,
    );
    if (sdkRoots.isEmpty) {
      logger?.fine('No Android SDK root candidates found.');
    } else {
      logger?.fine('Android SDK root candidates: $sdkRoots');
    }

    final ndkCandidates = await _collectNdkRootCandidates(
      sdkRoots: sdkRoots,
      environment: env,
      logger: logger,
    );
    if (ndkCandidates.isEmpty) {
      logger?.fine('No Android NDK candidates found.');
      return const [];
    }
    logger?.fine('Android NDK candidates (priority order): $ndkCandidates');

    // Optional user-defined version filter.
    var filtered = ndkCandidates;
    final requestedNdkVersion = userConfig?.ndkVersion;
    if (requestedNdkVersion != null) {
      final target = Version.parse(requestedNdkVersion);
      final kept = <({Uri uri, Version? version})>[];
      for (final c in ndkCandidates) {
        if (c.version == target) {
          kept.add(c);
        } else {
          logger?.warning(
            'Skipping NDK candidate ${c.uri} (version=${c.version}) '
            'because it does not match requested ndk_version=$target.',
          );
        }
      }
      if (kept.isEmpty) {
        logger?.severe('Failed to find NDK version: $requestedNdkVersion');
        throw Exception('Failed to find NDK version: $requestedNdkVersion');
      }
      filtered = kept;
    }

    final ndkInstances = <ToolInstance>[];
    var toolInstances = const <ToolInstance>[];
    for (final c in filtered) {
      ndkInstances.add(ToolInstance(tool: androidNdk, uri: c.uri, version: c.version));
      if (toolInstances.isEmpty) {
        // `getNdkBinaryPath` semantics: tools come from the first NDK that
        // actually contains them. Stop probing once any tools are found.
        final tools = await _resolveToolsForNdk(c.uri, logger: logger);
        if (tools.isNotEmpty) {
          toolInstances = tools;
        }
      }
    }

    return [...ndkInstances, ...toolInstances];
  }

  /// Builds the ordered, de-duplicated list of Android SDK root candidates.
  ///
  /// Resolution order (matches Flutter `AndroidSdk.locateAndroidSdk`):
  ///   1. [UserConfig.androidHome]
  ///   2. `ANDROID_HOME` environment variable
  ///   3. Platform-default install location
  ///   4. For each hit above also try `<dir>/sdk` (legacy layout)
  ///   5. `aapt` on PATH -> parent.parent.parent if it passes
  ///      [_validSdkDirectory]
  ///   6. `adb` on PATH -> parent.parent if it passes [_validSdkDirectory]
  Future<List<Uri>> _collectSdkRootCandidates({
    required Map<String, String> environment,
    UserConfig? userConfig,
    Logger? logger,
  }) async {
    final candidates = <Uri>[];
    final seen = <String>{};

    void addIfValid(String raw) {
      if (raw.isEmpty) return;
      final dir = Directory(raw).absolute.uri.normalizePath();
      if (_tryAdd(dir, candidates, seen)) return;
      // Legacy `<home>/sdk` fallback used when ANDROID_HOME points at the
      // user home rather than the SDK itself.
      _tryAdd(dir.resolve('sdk/'), candidates, seen);
    }

    // 1. userConfig.androidHome (already normalised to forward slashes).
    if (userConfig?.androidHome != null) {
      addIfValid(userConfig!.androidHome!);
    }

    // 2. ANDROID_HOME env var.
    final envHome = environment[kAndroidHome];
    if (envHome != null && envHome.isNotEmpty) {
      addIfValid(envHome);
    }

    // 3. Platform-default install location.
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final defaultPath = switch (Platform.operatingSystem) {
        'linux' => '$home/Android/Sdk',
        'macos' => '$home/Library/Android/sdk',
        'windows' => '$home/AppData/Local/Android/Sdk',
        _ => null,
      };
      if (defaultPath != null) addIfValid(defaultPath);
    }

    // 5/6. PATH aapt / adb reverse discovery.
    // SDK layout: $SDK/build-tools/<v>/aapt     -> parent.parent.parent == SDK
    //             $SDK/platform-tools/adb        -> parent.parent     == SDK
    for (final aaptBin in await _whichAll('aapt', logger: logger, environment: environment)) {
      addIfValid(aaptBin.resolve('../../..').toFilePath());
    }
    for (final adbBin in await _whichAll('adb', logger: logger, environment: environment)) {
      addIfValid(adbBin.resolve('../..').toFilePath());
    }

    return candidates;
  }

  /// Inserts [dir] into [candidates] if it is a valid SDK root and has not
  /// been added yet. Returns `true` when the directory is either freshly
  /// added or was already present in [seen] (so callers can use its return
  /// value to skip the legacy `<dir>/sdk` fallback without adding a
  /// redundant second entry).
  static bool _tryAdd(Uri dir, List<Uri> candidates, Set<String> seen) {
    if (!_validSdkDirectory(dir)) return false;
    final key = dir.toString();
    if (seen.contains(key)) return true;
    seen.add(key);
    candidates.add(dir);
    return true;
  }

  /// Whether [dir] looks like an Android SDK root. Mirrors Flutter
  /// `AndroidSdk.validSdkDirectory` (must contain `platform-tools/` or
  /// `licenses/`).
  static bool _validSdkDirectory(Uri dir) {
    return Directory.fromUri(dir.resolve('platform-tools/')).existsSync() ||
        Directory.fromUri(dir.resolve('licenses/')).existsSync();
  }

  /// Returns every executable named [name] found on `PATH`.
  ///
  /// Uses `where` on Windows and `which -a` on POSIX, then resolves symlinks.
  /// Failures (binary not installed) return an empty list so callers can chain
  /// without try/catch.
  Future<List<Uri>> _whichAll(String name, {Logger? logger, Map<String, String>? environment}) async {
    final executable = Uri.file(Platform.isWindows ? 'where.exe' : 'which');
    final arguments = [if (!Platform.isWindows) '-a', name];
    try {
      // `where` on Windows matches the pattern against the extensions listed in
      // PATHEXT. Environments passed to build hooks (e.g. by hooks_runner) are
      // filtered to an allowlist that does not include PATHEXT, so without a
      // fallback `where cmake` would not match `cmake.exe`.
      final hasUsablePathext =
          environment?.entries.any(
            (entry) => entry.key.toLowerCase() == 'pathext' && entry.value.trim().isNotEmpty,
          ) ??
          false;
      final environmentWithPathext = Platform.isWindows && !hasUsablePathext
          ? {
              if (environment != null) ...environment,
              'PATHEXT': '.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC;.CPL',
            }
          : environment;
      final result = await runProcess(
        executable: executable,
        arguments: arguments,
        logger: logger,
        environment: environmentWithPathext,
        captureOutput: true,
        throwOnUnexpectedExitCode: false,
      );
      if (result.exitCode != 0) return const [];
      final out = <Uri>[];
      for (final raw in LineSplitter.split(result.stdout)) {
        final path = raw.trim();
        if (path.isEmpty) continue;
        final file = File(path);
        try {
          if (await file.exists()) {
            out.add(File(await file.resolveSymbolicLinks()).uri);
          }
        } on FileSystemException {
          // Stale entry / disappeared between `which` and the existence check.
        }
      }
      return out;
    } on ProcessException {
      return const [];
    }
  }

  /// Builds the ordered, de-duplicated list of NDK root candidates.
  ///
  /// Resolution order (matches Flutter `getNdkDirectoriesInResolutionOrder`):
  ///   1. `ANDROID_NDK_HOME`
  ///   2. `ANDROID_NDK_PATH`
  ///   3. `ANDROID_NDK_ROOT`
  ///   4. For each entry in [sdkRoots]: `<root>/ndk/<version>/` enumerated in
  ///      descending `Version.parse` order (entries that don't parse are
  ///      skipped). Linux-only legacy `<root>/ndk-bundle/` is appended
  ///      afterwards.
  ///   5. `ndk-build` on PATH (lowest priority fallback).
  Future<List<({Uri uri, Version? version})>> _collectNdkRootCandidates({
    required List<Uri> sdkRoots,
    required Map<String, String> environment,
    Logger? logger,
  }) async {
    final out = <({Uri uri, Version? version})>[];
    final seen = <String>{};

    void addIfNew(Uri uri, {Version? version}) {
      final key = uri.toString();
      if (seen.contains(key)) return;
      seen.add(key);
      out.add((uri: uri, version: version));
    }

    // 1-3. NDK env vars (verbatim NDK root paths).
    for (final v in const [kAndroidNdkHome, kAndroidNdkPath, kAndroidNdkRoot]) {
      final path = environment[v];
      if (path == null || path.isEmpty) continue;
      final uri = Directory(path).absolute.uri.normalizePath();
      if (Directory.fromUri(uri).existsSync()) {
        addIfNew(uri, version: _tryParseVersion(uri));
      } else {
        logger?.warning('$v=$path does not exist, ignoring.');
      }
    }

    // 4. <sdkRoot>/ndk/<v>/ discovery + Linux ndk-bundle.
    for (final sdkDir in sdkRoots) {
      final ndkDir = sdkDir.resolve('ndk/');
      final ndkDirectory = Directory.fromUri(ndkDir);
      if (ndkDirectory.existsSync()) {
        final versions = <Version>[];
        for (final entity in ndkDirectory.listSync()) {
          if (entity is! Directory) continue;
          try {
            versions.add(Version.parse(_basename(entity.uri)));
          } on Exception {
            // Mirror Flutter `getNdkDirectoriesInResolutionOrder`:
            // entries whose dirname is not a parseable Version are skipped.
          }
        }
        versions.sort((a, b) => -a.compareTo(b));
        for (final v in versions) {
          addIfNew(ndkDir.resolve('$v/'), version: v);
        }
      }
      if (Platform.isLinux) {
        // Pre-`ndk/<v>/` layout where the single NDK lived under
        // `<sdk>/ndk-bundle/`.
        final ndkBundle = sdkDir.resolve('ndk-bundle/');
        if (Directory.fromUri(ndkBundle).existsSync()) {
          addIfNew(ndkBundle, version: null);
        }
      }
    }

    // 5. ndk-build on PATH (lowest priority).
    final ndkBuildResolver = PathToolResolver(
      toolName: 'ndk-build',
      executableName: Platform.isWindows ? 'ndk-build.cmd' : 'ndk-build',
    );
    final ndkBuildInstances = await ndkBuildResolver.resolve(logger: logger, environment: environment);
    for (final instance in ndkBuildInstances) {
      // `<ndk>/ndk-build(.cmd)` -> NDK root is parent.
      addIfNew(instance.uri.resolve('..').normalizePath(), version: null);
    }

    return out;
  }

  /// Resolves `clang`, `llvm-ar`, `ld.lld` binaries bundled with [ndkRoot].
  ///
  /// Probes the single host directory documented by the NDK for the current
  /// operating system first (see [_llvmHostDirectoryName]). If that directory
  /// does not exist falls back to listing every entry under `prebuilt/` so
  /// future host triples (e.g. `darwin-arm64`) keep working. The previous
  /// implementation had a copy-paste bug where the `ld.lld` existence check
  /// used the `llvm-ar` path; this is fixed here.
  Future<List<ToolInstance>> _resolveToolsForNdk(Uri ndkRoot, {Logger? logger}) async {
    final prebuiltBase = ndkRoot.resolve('toolchains/llvm/prebuilt/');

    final probes = <Uri>[];
    final hostName = _llvmHostDirectoryName[Platform.operatingSystem];
    if (hostName != null) {
      final known = prebuiltBase.resolve('$hostName/');
      if (Directory.fromUri(known).existsSync()) {
        probes.add(known);
      }
    }
    if (probes.isEmpty) {
      final prebuiltDir = Directory.fromUri(prebuiltBase);
      if (prebuiltDir.existsSync()) {
        for (final entity in prebuiltDir.listSync()) {
          if (entity is Directory) probes.add(entity.uri.normalizePath());
        }
      }
    }

    final result = <ToolInstance>[];
    for (final hostDir in probes) {
      final bin = hostDir.resolve('bin/');
      await _addVersionedTool(result, bin, 'clang', androidNdkClang, logger: logger);
      await _addVersionedTool(result, bin, 'llvm-ar', androidNdkLlvmAr, logger: logger);
      await _addVersionedTool(result, bin, 'ld.lld', androidNdkLld, logger: logger);
    }
    return result;
  }

  /// Adds the version-resolved [tool] under [binDir] to [result] if the
  /// executable exists. No-op otherwise.
  static Future<void> _addVersionedTool(
    List<ToolInstance> result,
    Uri binDir,
    String exeName,
    Tool tool, {
    Logger? logger,
  }) async {
    final uri = binDir.resolve(OS.current.executableFileName(exeName));
    if (!await File.fromUri(uri).exists()) return;
    result.add(
      await CliVersionResolver.lookupVersion(
        ToolInstance(tool: tool, uri: uri),
        logger: logger,
      ),
    );
  }

  /// Parses the last non-empty path segment of [uri] as a [Version].
  static Version? _tryParseVersion(Uri uri) {
    try {
      return Version.parse(_basename(uri));
    } on Exception {
      return null;
    }
  }

  /// Returns the last non-empty path segment of [uri].
  static String _basename(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? '' : segments.last;
  }
}
