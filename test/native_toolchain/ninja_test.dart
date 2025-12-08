import 'dart:io';

import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/ninja.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('ninja', () async {
    final ninjaTools = await ninja.defaultResolver!.resolve(logger: logger);
    expect(ninjaTools, isNotEmpty);
  });

  test('Android Ninja test', () async {
    final androidHome = Platform.environment['ANDROID_HOME'];
    final tools = await ninja.defaultResolver!.resolve(
      logger: logger,
      userConfig: UserConfig(androidHome: androidHome, preferAndroidNinja: true),
    );
    expect(tools, isNotEmpty);
    if (androidHome != null) {
      expect(File.fromUri(tools.first.uri).path, startsWith(androidHome));
    }
  });
}
