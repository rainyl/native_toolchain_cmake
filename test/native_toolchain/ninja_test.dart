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
    final ninjaTool = await ninja.defaultResolver!.resolve(
      logger: logger,
      userConfig: UserConfig(preferAndroidNinja: true),
    );
    expect(ninjaTool, isNotEmpty);
  });
}
