import 'dart:io';

import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('CMake System', () async {
    final tools = await cmake.defaultResolver!.resolve(logger: logger);
    expect(tools, isNotEmpty);
  });

  test('CMake Android', () async {
    final androidHome = Platform.environment['ANDROID_HOME'];
    final tools = await cmake.defaultResolver!.resolve(
      logger: logger,
      userConfig: UserConfig(
        androidHome: androidHome,
        preferAndroidCmake: true,
        // cmakeVersion: "3.22.1",
        // ninjaVersion: "1.10.2",
      ),
    );
    expect(tools, isNotEmpty);
    if (androidHome != null) {
      expect(File.fromUri(tools.first.uri).path, startsWith(androidHome));
    }
  });
}
