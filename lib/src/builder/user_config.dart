// Copyright (c) 2025, jasaw and rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

class UserConfig {
  final String? androidHome;
  final String? cmakeVersion;
  final bool preferAndroidCmake;
  final String? ninjaVersion;
  final bool preferAndroidNinja;
  final String? ndkVersion;

  const UserConfig({
    this.androidHome,
    this.cmakeVersion,
    this.preferAndroidCmake = false,
    this.preferAndroidNinja = false,
    this.ninjaVersion,
    this.ndkVersion,
  });

  UserConfig copyWith({
    String? androidHome,
    String? cmakeVersion,
    bool preferAndroidCmake = false,
    bool preferAndroidNinja = false,
    String? ninjaVersion,
    String? ndkVersion,
  }) => UserConfig(
    androidHome: androidHome ?? this.androidHome,
    cmakeVersion: cmakeVersion ?? this.cmakeVersion,
    preferAndroidCmake: preferAndroidCmake,
    preferAndroidNinja: preferAndroidNinja,
    ninjaVersion: ninjaVersion ?? this.ninjaVersion,
    ndkVersion: ndkVersion ?? this.ndkVersion,
  );
}
