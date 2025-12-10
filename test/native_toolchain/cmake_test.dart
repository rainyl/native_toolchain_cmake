import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  for (final preferAndroid in [null, false, true]) {
    test('System CMake preferAndroid=$preferAndroid', () async {
      final userConfig = UserConfig(
        targetOS: OS.current,
        androidHome: null,
        preferAndroidCmake: preferAndroid,
        // cmakeVersion: "3.22.1"
      );
      final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);
      expect(tools, isNotEmpty);
      if (userConfig.targetOS != OS.android && !userConfig.preferAndroidCmake) {
        expect(tools.length, 1);
      }
      // print(tools);
    });

    test('Android CMake preferAndroid=$preferAndroid', () async {
      final androidHome = Platform.environment['ANDROID_HOME'];
      final userConfig = UserConfig(
        targetOS: OS.android,
        androidHome: androidHome,
        preferAndroidCmake: preferAndroid,
        // cmakeVersion: "3.22.1"
      );
      final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);
      expect(tools, isNotEmpty);
      // print(tools);
    });
  }
}
