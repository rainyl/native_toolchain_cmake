// Copyright (c) 2025, jasaw and rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

class UserConfig {
  final String? androidHome;
  final String? cmakeVersion;
  final bool preferAndroidCmake;
  final String? androidTargetCmakeVersion;
  final String? ninjaVersion;
  final bool preferAndroidNinja;
  final String? androidTargetNinjaVersion;
  final String? ndkVersion;

  const UserConfig({
    this.androidHome,
    this.cmakeVersion,
    this.preferAndroidCmake = false,
    this.androidTargetCmakeVersion,
    this.preferAndroidNinja = false,
    this.ninjaVersion,
    this.androidTargetNinjaVersion,
    this.ndkVersion,
  });

  UserConfig copyWith({
    String? androidHome,
    String? cmakeVersion,
    bool preferAndroidCmake = false,
    String? androidTargetCmakeVersion,
    String? ninjaVersion,
    bool preferAndroidNinja = false,
    String? androidTargetNinjaVersion,
    String? ndkVersion,
  }) => UserConfig(
    androidHome: androidHome ?? this.androidHome,
    cmakeVersion: cmakeVersion ?? this.cmakeVersion,
    preferAndroidCmake: preferAndroidCmake,
    androidTargetCmakeVersion: androidTargetCmakeVersion ?? this.androidTargetCmakeVersion,
    ninjaVersion: ninjaVersion ?? this.ninjaVersion,
    preferAndroidNinja: preferAndroidNinja,
    androidTargetNinjaVersion: androidTargetNinjaVersion ?? this.androidTargetNinjaVersion,
    ndkVersion: ndkVersion ?? this.ndkVersion,
  );
}
