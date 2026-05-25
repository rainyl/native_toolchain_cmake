// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
//
// This file is adapted from https://github.com/dart-lang/native/tree/main/pkgs/native_toolchain_c
// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../builder/user_config.dart';
import '../tool/tool.dart';
import '../tool/tool_instance.dart';
import '../tool/tool_resolver.dart';
import 'clang.dart';

final androidNdk = Tool(name: 'Android NDK', defaultResolver: _AndroidNdkResolver());

/// [clang] with [Tool.defaultResolver] for the [OS.android] NDK.
final androidNdkClang = Tool(name: clang.name, defaultResolver: _AndroidNdkResolver());

/// [llvmAr] with [Tool.defaultResolver] for the [OS.android] NDK.
final androidNdkLlvmAr = Tool(name: llvmAr.name, defaultResolver: _AndroidNdkResolver());

/// [lld] with [Tool.defaultResolver] for the [OS.android] NDK.
final androidNdkLld = Tool(name: lld.name, defaultResolver: _AndroidNdkResolver());

class _AndroidNdkResolver implements ToolResolver {
  // No official environment variable for the NDK root is documented:
  // https://developer.android.com/tools/variables#envar
  // The following three are the most commonly used (see flutter_android_sdk.dart:23-28).
  static const _ndkEnvVars = ['ANDROID_NDK_HOME', 'ANDROID_NDK_PATH', 'ANDROID_NDK_ROOT'];
  // ANDROID_SDK_ROOT is deprecated, see https://developer.android.com/studio/command-line/variables.html#envar
  // but here we still check it.
  static const _androidSdkRoot = 'ANDROID_SDK_ROOT';
  static const _androidHome = 'ANDROID_HOME';

  @override
  Future<List<ToolInstance>> resolve({
    required Logger? logger,
    UserConfig? userConfig,
    Map<String, String>? environment,
  }) async {
    final List<ToolInstance> ndkInstances = [];

    // Step 1: Check ANDROID_NDK_HOME, ANDROID_NDK_PATH, ANDROID_NDK_ROOT env vars.
    for (final envVar in _ndkEnvVars) {
      final ndkPath = environment?[envVar] ?? Platform.environment[envVar];
      if (ndkPath != null && ndkPath.isNotEmpty) {
        final ndkDir = Directory(ndkPath);
        if (await ndkDir.exists()) {
          logger?.fine('Found Android NDK via $envVar=$ndkPath');
          ndkInstances.add(
            ToolInstance(
              tool: Tool(name: 'Android NDK'),
              uri: ndkDir.absolute.uri,
            ),
          );
          break; // Use the first found (highest priority) env var.
        }
      }
    }

    // Step 2: Resolve androidHome — try userConfig, env vars, OS defaults, then PATH discovery (aapt/adb).
    final androidHome = await _resolveAndroidHome(
      logger: logger,
      userConfig: userConfig,
      environment: environment,
    );

    // Step 3: Look for ndk-build on PATH, then fall back to androidHome/ndk/*/ and OS default install locations.
    final installLocationResolver = PathVersionResolver(
      wrappedResolver: ToolResolvers([
        RelativeToolResolver(
          toolName: 'Android NDK',
          wrappedResolver: PathToolResolver(
            toolName: 'ndk-build',
            executableName: Platform.isWindows ? 'ndk-build.cmd' : 'ndk-build',
          ),
          relativePath: Uri(path: ''),
        ),
        InstallLocationResolver(
          toolName: 'Android NDK',
          paths: [
            if (androidHome != null) ...[
              '$androidHome/ndk/*/',
              if (Platform.isLinux) '$androidHome/ndk-bundle/',
            ],
            if (androidHome == null) ...[
              if (Platform.isLinux) ...[r'$HOME/Android/Sdk/ndk/*/', r'$HOME/Android/Sdk/ndk-bundle/'],
              if (Platform.isMacOS) r'$HOME/Library/Android/sdk/ndk/*/',
              if (Platform.isWindows) r'$HOME/AppData/Local/Android/Sdk/ndk/*/',
            ],
          ],
        ),
      ]),
    );

    ndkInstances.addAll(await installLocationResolver.resolve(logger: logger, environment: environment));

    // Apply version from path to env-based instances too (safe: skips already-versioned).
    for (var i = 0; i < ndkInstances.length; i++) {
      ndkInstances[i] = PathVersionResolver.lookupVersion(ndkInstances[i]);
    }

    // Deduplicate by URI — env var instances (added first) take priority.
    final seenUris = <Uri>{};
    ndkInstances.removeWhere((instance) => !seenUris.add(instance.uri));

    // sort latest version first
    ndkInstances.sort(
      (a, b) => switch ((a.version, b.version)) {
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
        (_, _) => -a.version!.compareTo(b.version!),
      },
    );
    if (userConfig?.ndkVersion != null) {
      final ndkVer = Version.parse(userConfig!.ndkVersion!);
      ndkInstances.removeWhere((ndkInstance) => ndkInstance.version != ndkVer);
      if (ndkInstances.isEmpty) {
        logger?.severe('Failed to find NDK version: ${userConfig.ndkVersion}');
        throw Exception('Failed to find NDK version: ${userConfig.ndkVersion}');
      }
    }

    return [
      for (final ndkInstance in ndkInstances) ...[
        ndkInstance,
        ...await tryResolveClang(ndkInstance, logger: logger),
      ],
    ];
  }

  /// Resolves androidHome following the same approach as Flutter's locateAndroidSdk:
  /// 1. androidHome from user config if set
  /// 2. `ANDROID_HOME` environment variable (with SDK validation)
  /// 3. `ANDROID_SDK_ROOT` environment variable (deprecated, with SDK validation)
  /// 4. OS-specific default install paths
  /// 5. PATH-based discovery via `aapt` (build-tools/$version/aapt → sdk root)
  /// 6. PATH-based discovery via `adb` (platform-tools/adb → sdk root)
  ///
  /// When a candidate directory does not validate, also tries `{dir}/sdk` subdirectory.
  static Future<String?> _resolveAndroidHome({
    required Logger? logger,
    UserConfig? userConfig,
    Map<String, String>? environment,
  }) async {
    String norm(String path) => path.replaceAll(r'\', '/');

    final home = userConfig?.androidHome;
    if (home != null) return norm(home);

    Uri toDirUri(String path) => Uri.directory(norm(path));

    bool isValidSdkDir(String path) {
      final uri = toDirUri(path);
      return Directory.fromUri(uri).existsSync() &&
          (Directory.fromUri(uri.resolve('platform-tools/')).existsSync() ||
              Directory.fromUri(uri.resolve('licenses/')).existsSync());
    }

    String? tryResolve(String path) {
      if (isValidSdkDir(path)) return norm(path);
      final sdkSub = toDirUri(path).resolve('sdk/').toFilePath();
      if (isValidSdkDir(sdkSub)) return norm(sdkSub);
      return null;
    }

    // ANDROID_HOME
    final envAndroidHome = environment?[_androidHome] ?? Platform.environment[_androidHome];
    if (envAndroidHome != null && envAndroidHome.isNotEmpty) {
      final result = tryResolve(envAndroidHome);
      if (result != null) {
        logger?.fine('Resolved ANDROID_HOME=$result');
        return result;
      }
    }

    // ANDROID_SDK_ROOT (deprecated)
    final envAndroidSdkRoot = environment?[_androidSdkRoot] ?? Platform.environment[_androidSdkRoot];
    if (envAndroidSdkRoot != null && envAndroidSdkRoot.isNotEmpty) {
      final result = tryResolve(envAndroidSdkRoot);
      if (result != null) {
        logger?.fine('Resolved ANDROID_SDK_ROOT=$result');
        return result;
      }
    }

    // OS-specific default paths
    final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (homeDir != null) {
      String? defaultPath;
      final homeUri = toDirUri(homeDir);
      if (Platform.isLinux) {
        defaultPath = homeUri.resolve('Android/Sdk/').toFilePath();
      } else if (Platform.isMacOS) {
        defaultPath = homeUri.resolve('Library/Android/sdk/').toFilePath();
      } else if (Platform.isWindows) {
        defaultPath = homeUri.resolve('AppData/Local/Android/Sdk/').toFilePath();
      }
      if (defaultPath != null) {
        final result = tryResolve(defaultPath);
        if (result != null) {
          logger?.fine('Resolved Android SDK at default path: $result');
          return result;
        }
      }
    }

    // PATH-based discovery via aapt (build-tools/$version/aapt → sdk root)
    logger?.finer('Looking for aapt on PATH to locate Android SDK.');
    final aaptName = Platform.isWindows ? 'aapt.exe' : 'aapt';
    final aaptUri = await PathToolResolver(
      toolName: 'aapt',
      executableName: aaptName,
    ).runWhich(logger: logger, environment: environment);
    if (aaptUri != null) {
      try {
        final resolved = await File.fromUri(aaptUri).resolveSymbolicLinks();
        final sdkDir = Uri.file(resolved).resolve('../..').toFilePath();
        final result = tryResolve(sdkDir);
        if (result != null) {
          logger?.fine('Resolved Android SDK via aapt: $result');
          return result;
        }
      } catch (_) {
        // Ignore symlink resolution errors.
      }
    }

    // PATH-based discovery via adb (platform-tools/adb → sdk root)
    logger?.finer('Looking for adb on PATH to locate Android SDK.');
    final adbName = Platform.isWindows ? 'adb.exe' : 'adb';
    final adbUri = await PathToolResolver(
      toolName: 'adb',
      executableName: adbName,
    ).runWhich(logger: logger, environment: environment);
    if (adbUri != null) {
      try {
        final resolved = await File.fromUri(adbUri).resolveSymbolicLinks();
        final sdkDir = Uri.file(resolved).resolve('..').toFilePath();
        final result = tryResolve(sdkDir);
        if (result != null) {
          logger?.fine('Resolved Android SDK via adb: $result');
          return result;
        }
      } catch (_) {
        // Ignore symlink resolution errors.
      }
    }

    return null;
  }

  Future<List<ToolInstance>> tryResolveClang(
    ToolInstance androidNdkInstance, {
    required Logger? logger,
  }) async {
    final result = <ToolInstance>[];
    final prebuiltUri = androidNdkInstance.uri.resolve('toolchains/llvm/prebuilt/');
    final prebuiltDir = Directory.fromUri(prebuiltUri);
    if (!await prebuiltDir.exists()) {
      logger?.finer('No toolchains/llvm/prebuilt in $androidNdkInstance, skipping clang resolution.');
      return result;
    }
    final hostArchDirs = (await prebuiltDir.list().toList()).whereType<Directory>().toList();
    for (final hostArchDir in hostArchDirs) {
      final clangUri = hostArchDir.uri.resolve('bin/').resolve(OS.current.executableFileName('clang'));
      if (await File.fromUri(clangUri).exists()) {
        result.add(
          await CliVersionResolver.lookupVersion(
            ToolInstance(tool: androidNdkClang, uri: clangUri),
            logger: logger,
          ),
        );
      }
      final arUri = hostArchDir.uri.resolve('bin/').resolve(OS.current.executableFileName('llvm-ar'));
      if (await File.fromUri(arUri).exists()) {
        result.add(
          await CliVersionResolver.lookupVersion(
            ToolInstance(tool: androidNdkLlvmAr, uri: arUri),
            logger: logger,
          ),
        );
      }
      final ldUri = hostArchDir.uri.resolve('bin/').resolve(OS.current.executableFileName('ld.lld'));
      if (await File.fromUri(arUri).exists()) {
        result.add(
          await CliVersionResolver.lookupVersion(
            ToolInstance(tool: androidNdkLld, uri: ldUri),
            logger: logger,
          ),
        );
      }
    }
    return result;
  }
}
