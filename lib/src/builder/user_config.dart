// Copyright (c) 2025, jasaw and rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';

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

  /// Per-OS sub-map keys indexed by [OS].
  static const osConfigKey = {
    OS.android: 'android',
    OS.iOS: 'ios',
    OS.linux: 'linux',
    OS.macOS: 'macos',
    OS.windows: 'windows',
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

  UserConfig({
    required this.targetOS,
    this.cmakeVersion,
    this.ninjaVersion,
    this.ndkVersion,
    String? androidHome,
    bool? preferAndroidCmake,
    bool? preferAndroidNinja,
    bool envVarAndroidHomeAsDefault = true,
  }) : preferAndroidCmake = preferAndroidCmake ?? targetOS == OS.android,
       preferAndroidNinja = preferAndroidNinja ?? targetOS == OS.android,
       androidHome =
           _normalizeAndroidHome(androidHome) ??
           (envVarAndroidHomeAsDefault ? _normalizeAndroidHome(Platform.environment['ANDROID_HOME']) : null);

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

    return UserConfig(
      targetOS: targetOS,
      cmakeVersion: cmakeVersion,
      ninjaVersion: ninjaVersion,
      ndkVersion: ndkVersion,
      androidHome: androidHome,
      preferAndroidCmake: preferCmake,
      preferAndroidNinja: preferNinja,
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
  }) => UserConfig(
    targetOS: targetOS ?? this.targetOS,
    androidHome: androidHome ?? this.androidHome,
    cmakeVersion: cmakeVersion ?? this.cmakeVersion,
    preferAndroidCmake: preferAndroidCmake ?? this.preferAndroidCmake,
    ninjaVersion: ninjaVersion ?? this.ninjaVersion,
    preferAndroidNinja: preferAndroidNinja ?? this.preferAndroidNinja,
    ndkVersion: ndkVersion ?? this.ndkVersion,
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
      'preferAndroidNinja: $preferAndroidNinja'
      ')';
}
