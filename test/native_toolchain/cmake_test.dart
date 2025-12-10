import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:mocktail/mocktail.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/cmake.dart';
import 'package:native_toolchain_cmake/src/tool/tool.dart';
import 'package:native_toolchain_cmake/src/tool/tool_instance.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mock_components.dart';

void main() {
  late MockCliVersionResolver mockAndroidResolver;
  late MockCliVersionResolver mockSystemResolver;

  setUp(() {
    mockAndroidResolver = MockCliVersionResolver();
    mockSystemResolver = MockCliVersionResolver();
    cmakeUnitTestAndroidResolver = mockAndroidResolver;
    cmakeUnitTestSystemResolver = mockSystemResolver;
  });

  group('Android target: ', () {
    test('one Android cmake, any version', () async {
      when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => [
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('android_cmake_path_1'),
              version: Version.parse('4.1.2')
            ),
          ]));
      when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
      final userConfig = UserConfig(
        targetOS: OS.android,
      );
      final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

      expect(tools.length, equals(1));
      expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_1')));
      expect(tools.first.version, equals(Version.parse('4.1.2')));
    });

    test('many Android cmake, latest version', () async {
      when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => [
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('android_cmake_path_1'),
              version: Version.parse('3.3.2')
            ),
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('android_cmake_path_2'),
              version: Version.parse('4.1.2')
            ),
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('android_cmake_path_3'),
              version: Version.parse('4.0.1')
            ),
          ]));
      when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
      final userConfig = UserConfig(
        targetOS: OS.android,
      );
      final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

      expect(tools.length, equals(3));
      expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_2')));
      expect(tools.first.version, equals(Version.parse('4.1.2')));
    });

    test('many Android cmake, user defined version', () async {
      when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => [
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('android_cmake_path_1'),
              version: Version.parse('3.3.2')
            ),
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('android_cmake_path_2'),
              version: Version.parse('4.1.2')
            ),
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('android_cmake_path_3'),
              version: Version.parse('4.0.1')
            ),
          ]));
      when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
      final userConfig = UserConfig(
        targetOS: OS.android,
        cmakeVersion: '4.0.1',
      );
      final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

      expect(tools.length, equals(1));
      expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_3')));
      expect(tools.first.version, equals(Version.parse('4.0.1')));
    });
  });

  // for (final preferAndroid in [null, false, true]) {
  //   test('System CMake preferAndroid=$preferAndroid', () async {
  //     final userConfig = UserConfig(
  //       targetOS: OS.current,
  //       androidHome: null,
  //       preferAndroidCmake: preferAndroid,
  //       // cmakeVersion: "3.22.1"
  //     );
  //     final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);
  //     expect(tools, isNotEmpty);
  //     if (userConfig.targetOS != OS.android && !userConfig.preferAndroidCmake) {
  //       expect(tools.length, 1);
  //     }
  //     // print(tools);
  //   });

  //   test('Android CMake preferAndroid=$preferAndroid', () async {
  //     final androidHome = Platform.environment['ANDROID_HOME'];
  //     final userConfig = UserConfig(
  //       targetOS: OS.android,
  //       androidHome: androidHome,
  //       preferAndroidCmake: preferAndroid,
  //       // cmakeVersion: "3.22.1"
  //     );
  //     final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);
  //     expect(tools, isNotEmpty);
  //     // print(tools);
  //   });
  // }
}
