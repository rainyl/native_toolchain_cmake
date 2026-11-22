// Copyright (c) 2025, jasaw and rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import '../utils/env_from_native_config.dart';

/// The [OS] used for WebAssembly / web builds.
///
/// `code_assets` does not define a web OS (web builds only support data
/// assets), so the builder uses a name-based [OS] value internally.
final OS webOS = OS.fromString('web');

/// Unwraps the `workspace_pubspec.defines` envelope that `package:hooks`
/// wraps `user_defines` in.
///
/// Accepts both the hooks envelope and a flat defines map. Non-map values are
/// logged and ignored.
Map<String, dynamic> unwrapUserDefines(Map<String, dynamic>? userDefines, {Logger? logger}) {
  if (userDefines == null) return const {};
  // Workspace envelope (hooks_runner / flutter build path).
  final workspace = userDefines['workspace_pubspec'];
  if (workspace is Map<String, dynamic>) {
    final defines = workspace['defines'];
    if (defines is Map<String, dynamic>) return defines;
    if (defines is Map) return defines.cast<String, dynamic>();
    if (defines != null) {
      logger?.warning(
        'user_defines.workspace_pubspec.defines expected Map, '
        'got ${defines.runtimeType}; ignored.',
      );
    }
    return const {};
  }
  // Direct flat defines (manual runStandalone / tests).
  return userDefines;
}

/// Keys allowed under the top-level `user_defines` map and (where applicable)
/// the per-OS sub-maps (`android`, `ios`, `linux`, `macos`, `windows`).
class UserConfigKeys {
  const UserConfigKeys._();

  static const cmakeVersion = 'cmake_version';
  static const ninjaVersion = 'ninja_version';
  static const ndkVersion = 'ndk_version';
  static const androidHome = 'android_home';
  static const envFile = 'env_file';
  static const preferAndroidCmake = 'prefer_android_cmake';
  static const preferAndroidNinja = 'prefer_android_ninja';

  /// Emscripten / web build configuration.
  static const emsdkPath = 'emsdk_path';
  static const emscriptenRoot = 'emscripten_root';
  static const emscriptenToolchainFile = 'emscripten_toolchain_file';
  static const emscriptenVersion = 'emscripten_version';

  /// Per-OS sub-map keys indexed by [OS].
  static final osConfigKey = {
    OS.android: 'android',
    OS.iOS: 'ios',
    OS.linux: 'linux',
    OS.macOS: 'macos',
    OS.windows: 'windows',
    webOS: 'web',
  };
}

class UserConfig {
  final OS targetOS;

  /// for [OS.android], i.e., ANDROID_HOME.
  ///
  /// Always stored with forward slashes only and without a trailing slash so
  /// it can be interpolated directly into glob patterns. `package:glob`
  /// treats `\` as an escape character rather than a path separator, so raw
  /// Windows paths obtained from `Platform.environment`, env files or
  /// `Directory.absolute.path` need to be normalised at construction time.
  /// Use [copyWith] / [parseFromUserDefines] to derive new instances so the
  /// invariant is preserved; do not assign this field manually from a
  /// non-normalised string.
  final String? androidHome;

  /// for [OS.android], if not specified, use the latest one
  final String? ndkVersion;

  /// for [OS.current], if not specified, use the latest one
  /// for [OS.android], [preferAndroidCmake] is assumed to be true by default, will try to use
  /// the android cmake if available, explicitly set it to false if you want to use the system cmake.
  final String? cmakeVersion;

  /// whether to prefer android cmake if available, for [OS.android], it is assumed to be true by default.
  /// explicitly set it to true for other platforms if you still want to use android cmake.
  final bool preferAndroidCmake;

  /// for [OS.current], if not specified, use the latest one
  /// for [OS.android], [preferAndroidNinja] is assumed to be true by default, will try to use
  /// the android ninja if available, explicitly set it to false if you want to use the system ninja.
  final String? ninjaVersion;

  /// whether to prefer android ninja if available, for [OS.android], it is assumed to be true by default.
  /// explicitly set it to true for other platforms if you still want to use android ninja.
  final bool preferAndroidNinja;

  /// Root of an emsdk checkout, e.g. `/opt/emsdk`.
  ///
  /// Only used for web builds. Stored with forward slashes like
  /// [androidHome].
  final String? emsdkPath;

  /// Root of an Emscripten installation, i.e. the directory containing
  /// `emcc` and `cmake/Modules/Platform/Emscripten.cmake`.
  final String? emscriptenRoot;

  /// Explicit path to `Emscripten.cmake`.
  final String? emscriptenToolchainFile;

  /// Optional Emscripten version pin, e.g. `3.1.51`.
  final String? emscriptenVersion;

  UserConfig({
    required this.targetOS,
    this.cmakeVersion,
    this.ninjaVersion,
    this.ndkVersion,
    String? androidHome,
    bool? preferAndroidCmake,
    bool? preferAndroidNinja,
    String? emsdkPath,
    String? emscriptenRoot,
    String? emscriptenToolchainFile,
    this.emscriptenVersion,
    bool envVarAndroidHomeAsDefault = true,
  }) : preferAndroidCmake = preferAndroidCmake ?? targetOS == OS.android,
       preferAndroidNinja = preferAndroidNinja ?? targetOS == OS.android,
       androidHome =
           _normalizeAndroidHome(androidHome) ??
           (envVarAndroidHomeAsDefault ? _normalizeAndroidHome(Platform.environment['ANDROID_HOME']) : null),
       emsdkPath = _normalizePath(emsdkPath),
       emscriptenRoot = _normalizePath(emscriptenRoot),
       emscriptenToolchainFile = _normalizePath(emscriptenToolchainFile);

  /// Normalises a path for safe interpolation into glob patterns and URIs:
  /// backslashes become forward slashes and trailing slashes are removed.
  static String? _normalizePath(String? path) {
    if (path == null) return null;
    final normalized = path.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
    return normalized.isEmpty ? null : normalized;
  }

  /// Normalises an [androidHome] path for safe interpolation into glob
  /// patterns: backslashes become forward slashes and trailing slashes are
  /// removed. `null` and empty strings are returned as `null`.
  static String? _normalizeAndroidHome(String? path) {
    if (path == null) return null;
    final normalized = path.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
    return normalized.isEmpty ? null : normalized;
  }

  /// Parses the `user_defines` map (as surfaced by `hooks`) into a [UserConfig].
  ///
  /// Resolution order for each scalar value:
  ///   1. the per-OS sub-map (`android`, `ios`, ...) entry, if present;
  ///   2. the top-level entry, if present;
  ///   3. `null` (left to the caller / [UserConfig] defaults to fill in).
  ///
  /// Keys with the wrong type are logged via [logger] at `warning` level and
  /// ignored rather than throwing a [TypeError]. This mirrors the lenient
  /// behaviour expected of build hooks where users edit YAML by hand.
  ///
  /// Android-only keys ([ndkVersion], [androidHome]) are read solely from the
  /// `android` sub-map regardless of [targetOS].
  ///
  /// System environment variable `ANDROID_HOME` is **not** consulted here; the
  /// caller decides whether to fall back to it. Pass
  /// `envVarAndroidHomeAsDefault: true` (the default) to [UserConfig] if that
  /// fallback is desired.
  // ignore: prefer_constructors_over_static_methods
  static UserConfig parseFromUserDefines({
    required OS targetOS,
    required Map<String, dynamic> userDefines,
    Logger? logger,
  }) {
    final osConfigKey = UserConfigKeys.osConfigKey[targetOS];
    final osConfig = osConfigKey == null ? null : _optMap(userDefines, osConfigKey, logger: logger);

    final cmakeVersion =
        _optString(osConfig, UserConfigKeys.cmakeVersion, logger: logger) ??
        _optString(userDefines, UserConfigKeys.cmakeVersion, logger: logger);
    final ninjaVersion =
        _optString(osConfig, UserConfigKeys.ninjaVersion, logger: logger) ??
        _optString(userDefines, UserConfigKeys.ninjaVersion, logger: logger);

    // Android-only keys, read only from the android sub-map.
    final androidConfig = _optMap(userDefines, UserConfigKeys.osConfigKey[OS.android]!, logger: logger);
    final ndkVersion = _optString(androidConfig, UserConfigKeys.ndkVersion, logger: logger);
    final androidHome = _optString(androidConfig, UserConfigKeys.androidHome, logger: logger);

    final preferCmake =
        _optBool(osConfig, UserConfigKeys.preferAndroidCmake, logger: logger) ??
        _optBool(userDefines, UserConfigKeys.preferAndroidCmake, logger: logger);
    final preferNinja =
        _optBool(osConfig, UserConfigKeys.preferAndroidNinja, logger: logger) ??
        _optBool(userDefines, UserConfigKeys.preferAndroidNinja, logger: logger);

    // Emscripten / web keys. Read from the per-OS (web) sub-map first, then
    // from the top level for convenience.
    final emsdkPath =
        _optString(osConfig, UserConfigKeys.emsdkPath, logger: logger) ??
        _optString(userDefines, UserConfigKeys.emsdkPath, logger: logger);
    final emscriptenRoot =
        _optString(osConfig, UserConfigKeys.emscriptenRoot, logger: logger) ??
        _optString(userDefines, UserConfigKeys.emscriptenRoot, logger: logger);
    final emscriptenToolchainFile =
        _optString(osConfig, UserConfigKeys.emscriptenToolchainFile, logger: logger) ??
        _optString(userDefines, UserConfigKeys.emscriptenToolchainFile, logger: logger);
    final emscriptenVersion =
        _optString(osConfig, UserConfigKeys.emscriptenVersion, logger: logger) ??
        _optString(userDefines, UserConfigKeys.emscriptenVersion, logger: logger);

    return UserConfig(
      targetOS: targetOS,
      cmakeVersion: cmakeVersion,
      ninjaVersion: ninjaVersion,
      ndkVersion: ndkVersion,
      androidHome: androidHome,
      preferAndroidCmake: preferCmake,
      preferAndroidNinja: preferNinja,
      emsdkPath: emsdkPath,
      emscriptenRoot: emscriptenRoot,
      emscriptenToolchainFile: emscriptenToolchainFile,
      emscriptenVersion: emscriptenVersion,
      envVarAndroidHomeAsDefault: false,
    );
  }

  /// Returns [map]?[key] when it is a [String], otherwise `null`.
  ///
  /// Logs a warning when the entry exists but has the wrong type. Tolerates
  /// numeric values (common from YAML where `3.22.1` parses as a double) by
  /// accepting them.
  static String? _optString(Map<String, dynamic>? map, String key, {Logger? logger}) {
    if (map == null) return null;
    final v = map[key];
    if (v == null) return null;
    if (v is String) return v;
    if (v is num) return v.toString();
    logger?.warning('user_defines.$key expected String or num, got ${v.runtimeType}; ignored.');
    return null;
  }

  /// Returns [map]?[key] when it is a [bool], otherwise `null`.
  static bool? _optBool(Map<String, dynamic>? map, String key, {Logger? logger}) {
    if (map == null) return null;
    final v = map[key];
    if (v == null) return null;
    if (v is bool) return v;
    logger?.warning('user_defines.$key expected bool, got ${v.runtimeType}; ignored.');
    return null;
  }

  /// Returns [map]?[key] when it is a [Map] with String keys, otherwise `null`.
  static Map<String, dynamic>? _optMap(Map<String, dynamic>? map, String key, {Logger? logger}) {
    if (map == null) return null;
    final v = map[key];
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    logger?.warning('user_defines.$key expected Map, got ${v.runtimeType}; ignored.');
    return null;
  }

  UserConfig copyWith({
    OS? targetOS,
    String? cmakeVersion,
    String? ninjaVersion,
    String? ndkVersion,
    String? androidHome,
    bool? preferAndroidCmake,
    bool? preferAndroidNinja,
    String? emsdkPath,
    String? emscriptenRoot,
    String? emscriptenToolchainFile,
    String? emscriptenVersion,
  }) => UserConfig(
    targetOS: targetOS ?? this.targetOS,
    androidHome: androidHome ?? this.androidHome,
    cmakeVersion: cmakeVersion ?? this.cmakeVersion,
    preferAndroidCmake: preferAndroidCmake ?? this.preferAndroidCmake,
    ninjaVersion: ninjaVersion ?? this.ninjaVersion,
    preferAndroidNinja: preferAndroidNinja ?? this.preferAndroidNinja,
    ndkVersion: ndkVersion ?? this.ndkVersion,
    emsdkPath: emsdkPath ?? this.emsdkPath,
    emscriptenRoot: emscriptenRoot ?? this.emscriptenRoot,
    emscriptenToolchainFile: emscriptenToolchainFile ?? this.emscriptenToolchainFile,
    emscriptenVersion: emscriptenVersion ?? this.emscriptenVersion,
    envVarAndroidHomeAsDefault: false,
  );

  @override
  String toString() =>
      'UserConfig('
      'targetOS: $targetOS, '
      'cmakeVersion: $cmakeVersion, '
      'ninjaVersion: $ninjaVersion, '
      'ndkVersion: $ndkVersion, '
      'androidHome: $androidHome, '
      'preferAndroidCmake: $preferAndroidCmake, '
      'preferAndroidNinja: $preferAndroidNinja, '
      'emsdkPath: $emsdkPath, '
      'emscriptenRoot: $emscriptenRoot, '
      'emscriptenToolchainFile: $emscriptenToolchainFile, '
      'emscriptenVersion: $emscriptenVersion'
      ')';
}

/// Parses the `hooks.user_defines` of this package into a [UserConfig], with
/// the same fallbacks for `AndroidCodeConfig`/`env_file` in both hooks.
Future<UserConfig> resolveUserConfig({
  required OS targetOS,
  required Map<String, dynamic> userDefines,
  HookInput? input,
  Uri? packageRoot,
  Logger? logger,
}) async {
  // hooks:
  //   user_defines:
  //     <package_name_that_use_native_toolchain_cmake>:
  //       env_file: ".env"
  //       cmake_version: "3.22.1"
  //       ninja_version: "1.10.2"
  //       prefer_android_cmake: false # defaults to true for android
  //       prefer_android_ninja: false # defaults to true for android
  //       android:
  //         android_home: "C:\\Android\\Sdk" # can be set in .env file
  //         ndk_version: "28.2.13676358"
  //         cmake_version: null # "3.22.1"
  //         ninja_version: null # "1.10.2"
  //       windows:
  //         cmake_version: null # "3.31.6"
  logger?.fine('userDefines: $userDefines');

  // Peel `workspace_pubspec.defines` if present (hooks_runner / flutter
  // build path). Direct callers passing the flat defines map are unaffected.
  final userDefinesFlat = unwrapUserDefines(userDefines, logger: logger);

  // Per-OS overrides win over the top-level entries; wrong types are logged
  // and ignored instead of throwing. See [UserConfig.parseFromUserDefines].
  var userConfig = UserConfig.parseFromUserDefines(
    targetOS: targetOS,
    userDefines: userDefinesFlat,
    logger: logger,
  );

  // Android-specific fallback chain for android_home:
  //   1. user_defines.android.android_home  (handled in parseFromUserDefines)
  //   2. env_file ANDROID_HOME              (handled below)
  //   3. ANDROID_HOME system env var        (handled below)
  // Each step only fills in when the previous one is null.
  final envFile = userDefinesFlat[UserConfigKeys.envFile];
  if (envFile is String && envFile.isNotEmpty) {
    final userEnvConfig = await getUserEnvConfig(input: input, packageRoot: packageRoot, envFile: envFile);
    final androidHome = userEnvConfig['ANDROID_HOME'];
    if (androidHome != null && userConfig.androidHome == null) {
      final androidHomeEntity = Directory(androidHome);
      if (androidHomeEntity.existsSync()) {
        userConfig = userConfig.copyWith(androidHome: androidHomeEntity.absolute.path);
      } else {
        logger?.warning('ANDROID_HOME=$androidHome is set in envFile=$envFile but does not exist, ignoring');
      }
    }
  } else if (envFile != null) {
    logger?.warning('user_defines.env_file expected String, got ${envFile.runtimeType}; ignored.');
  }

  // Last-resort fallback to the ANDROID_HOME system environment variable.
  if (userConfig.androidHome == null) {
    final envAndroidHome = Platform.environment['ANDROID_HOME'];
    if (envAndroidHome != null && envAndroidHome.isNotEmpty) {
      final dir = Directory(envAndroidHome);
      if (dir.existsSync()) {
        userConfig = userConfig.copyWith(androidHome: dir.absolute.path);
      } else {
        logger?.warning('ANDROID_HOME=$envAndroidHome from environment does not exist, ignoring.');
      }
    }
  }

  logger?.fine('Resolved userConfig: $userConfig');
  return userConfig;
}
