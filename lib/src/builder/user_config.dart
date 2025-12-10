// Copyright (c) 2025, jasaw and rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';

class UserConfig {
  final OS targetOS;

  /// for [OS.android], i.e., ANDROID_HOME, will try to load from environment variable if not specified.
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
  }) : preferAndroidCmake = preferAndroidCmake ?? targetOS == OS.android,
       preferAndroidNinja = preferAndroidNinja ?? targetOS == OS.android,
       androidHome = androidHome ?? Platform.environment['ANDROID_HOME'];

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
  );
}
