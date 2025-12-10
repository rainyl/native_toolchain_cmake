import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/ninja.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  for (final preferAndroid in [null, false, true]) {
    test('System ninja preferAndroid=$preferAndroid', () async {
      final userConfig = UserConfig(
        targetOS: OS.android,
        androidHome: null,
        preferAndroidNinja: preferAndroid,
        // ninjaVersion: "1.10.2"
      );
      final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);
      expect(tools, isNotEmpty);
      if (userConfig.targetOS != OS.android && !userConfig.preferAndroidCmake) {
        expect(tools.length, 1);
      }
      if (userConfig.androidHome != null && userConfig.preferAndroidNinja) {
        expect(File.fromUri(tools.first.uri).path, startsWith(userConfig.androidHome!));
      }
    });

    test('Android Ninja preferAndroid=$preferAndroid', () async {
      final androidHome = Platform.environment['ANDROID_HOME'];
      final userConfig = UserConfig(
        targetOS: OS.android,
        androidHome: androidHome,
        preferAndroidNinja: preferAndroid,
        // ninjaVersion: "1.10.2"
      );
      final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);
      expect(tools, isNotEmpty);
      // print(tools);
      if (userConfig.androidHome != null && userConfig.preferAndroidNinja) {
        expect(File.fromUri(tools.first.uri).path, startsWith(userConfig.androidHome!));
      }
    });
  }
}
