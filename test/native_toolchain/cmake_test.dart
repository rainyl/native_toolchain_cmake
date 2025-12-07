import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('CMake System', () async {
    final tools = await cmake.defaultResolver!.resolve(logger: logger);
    expect(tools, isNotEmpty);
    print(tools.map((e) => e.version).join(', '));
  });

  test('CMake Android', () async {
    final tools = await cmake.defaultResolver!.resolve(
      logger: logger,
      userConfig: UserConfig(preferAndroidCmake: true),
    );
    expect(tools, isNotEmpty);
    print(tools.map((e) => e.version).join(', '));
  });
}
