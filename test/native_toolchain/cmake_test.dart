import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:mocktail/mocktail.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/cmake.dart';
import 'package:native_toolchain_cmake/src/tool/tool.dart';
import 'package:native_toolchain_cmake/src/tool/tool_instance.dart';
import 'package:native_toolchain_cmake/src/tool/tool_resolver.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mock_components.dart';

void main() {
  late MockCliVersionResolver mockAndroidResolver;
  late MockCliVersionResolver mockSystemResolver;

  group('Install location: ', () {
    final List<String> pathsSearched = [];
    Future<List<Uri>> mockTryResolvePath(String path) async {
      pathsSearched.add(path);
      return [];
    }
    
    setUp(() {
      mockSystemResolver = MockCliVersionResolver();
      unitTestCmakeSystemResolver = mockSystemResolver;
      pathsSearched.clear();
      InstallLocationResolver.unitTestTryResolvePath = mockTryResolvePath;
    });

    test('Android home not set', () async {
      when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => [
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('system_cmake_path_1'),
              version: Version.parse('4.1.2')
            ),
          ]));
      final userConfig = UserConfig(
        targetOS: OS.android,
      );

      final executableName = OS.current.executableFileName('cmake');
      String expectedSearchPath = executableName;
      if (Platform.isLinux) {
        expectedSearchPath = r'$HOME/Android/Sdk/cmake/*/bin/' + expectedSearchPath;
      } else if (Platform.isMacOS) {
        expectedSearchPath = r'$HOME/Library/Android/sdk/cmake/*/bin/' + expectedSearchPath;
      } else if (Platform.isWindows) {
        expectedSearchPath = r'$HOME/AppData/Local/Android/Sdk/cmake/*/bin/' + expectedSearchPath;
      }
      
      final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

      expect(pathsSearched.length, equals(1));
      expect(pathsSearched.first, equals(expectedSearchPath));
      expect(tools.length, equals(1));
      expect(tools.first.uri, equals(Uri.dataFromString('system_cmake_path_1')));
      expect(tools.first.version, equals(Version.parse('4.1.2')));
    });

    test('Android home is set', () async {
      when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => [
            ToolInstance(
              tool: Tool(name: 'CMake'),
              uri: Uri.dataFromString('system_cmake_path_1'),
              version: Version.parse('4.1.2')
            ),
          ]));
      final userConfig = UserConfig(
        targetOS: OS.android,
        androidHome: 'my/android/home',
      );

      final executableName = OS.current.executableFileName('cmake');
      String expectedSearchPath = executableName;
      if (Platform.isLinux) {
        expectedSearchPath = r'$HOME/Android/Sdk/cmake/*/bin/' + expectedSearchPath;
      } else if (Platform.isMacOS) {
        expectedSearchPath = r'$HOME/Library/Android/sdk/cmake/*/bin/' + expectedSearchPath;
      } else if (Platform.isWindows) {
        expectedSearchPath = r'$HOME/AppData/Local/Android/Sdk/cmake/*/bin/' + expectedSearchPath;
      }
      
      final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

      expect(pathsSearched.length, equals(2));
      expect(pathsSearched.first, equals('my/android/home/cmake/*/bin/$executableName'));
      expect(pathsSearched[1], equals(expectedSearchPath));
      expect(tools.length, equals(1));
      expect(tools.first.uri, equals(Uri.dataFromString('system_cmake_path_1')));
      expect(tools.first.version, equals(Version.parse('4.1.2')));
    });
  });

  group('CMake selection: ', () {
    setUp(() {
      mockAndroidResolver = MockCliVersionResolver();
      mockSystemResolver = MockCliVersionResolver();
      unitTestCmakeAndroidResolver = mockAndroidResolver;
      unitTestCmakeSystemResolver = mockSystemResolver;
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

      test('one Android cmake, no system cmake, prefers system cmake', () async {
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
          preferAndroidCmake: false,
        );

        expect(() async => cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig), throwsA(isA<Exception>()));
      });

      test('no Android cmake, has system cmake', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.android,
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_cmake_path_1')));
        expect(tools.first.version, equals(Version.parse('4.1.2')));
      });

      test('no Android cmake, has system cmake, prefers Android cmake', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.android,
          preferAndroidCmake: true,
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_cmake_path_1')));
        expect(tools.first.version, equals(Version.parse('4.1.2')));
      });

      test('many Android cmake, has system cmake, user defined version', () async {
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
                version: Version.parse('4.2.2')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_3'),
                version: Version.parse('4.0.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.android,
          cmakeVersion: "4.1.2"
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_cmake_path_1')));
        expect(tools.first.version, equals(Version.parse('4.1.2')));
      });
    });

    group('iOS target: ', () {
      test('one Android cmake, no system cmake', () async {
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
          targetOS: OS.iOS,
        );

        expect(() async => cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig), throwsA(isA<Exception>()));
      });

      test('one Android cmake, no system cmake, do not prefer Android cmake', () async {
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
          targetOS: OS.iOS,
          preferAndroidCmake: false,
        );

        expect(() async => cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig), throwsA(isA<Exception>()));
      });

      test('one Android cmake, no system cmake, prefer Android cmake, any version', () async {
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
          targetOS: OS.iOS,
          preferAndroidCmake: true,
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_1')));
        expect(tools.first.version, equals(Version.parse('4.1.2')));
      });

      test('one Android cmake, no system cmake, prefer Android cmake, user defined version', () async {
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
          targetOS: OS.iOS,
          preferAndroidCmake: true,
          cmakeVersion: "4.1.2",
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_1')));
        expect(tools.first.version, equals(Version.parse('4.1.2')));
      });

      test('one Android cmake, no system cmake, prefer Android cmake, user defined version not found', () async {
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
          targetOS: OS.iOS,
          preferAndroidCmake: true,
          cmakeVersion: "4.1.3",
        );
        expect(() async => cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig), throwsA(isA<Exception>()));
      });

      test('one Android cmake, one system cmake, do not prefer Android cmake, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          cmakeVersion: "4.1.2",
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_cmake_path_1')));
        expect(tools.first.version, equals(Version.parse('4.1.2')));
      });

      test('one Android cmake, one system cmake, prefer Android cmake, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          preferAndroidCmake: true,
          cmakeVersion: "4.1.2",
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(2));
        expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_1')));
        expect(tools.first.version, equals(Version.parse('4.1.2')));
      });

      test('many Android cmake, one system cmake, prefer Android cmake, latest version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_2'),
                version: Version.parse('4.1.5')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_3'),
                version: Version.parse('4.1.4')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.3')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          preferAndroidCmake: true,
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(4));
        expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_2')));
        expect(tools.first.version, equals(Version.parse('4.1.5')));
      });

      test('many Android cmake, one system cmake, do not prefer Android cmake, latest version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_2'),
                version: Version.parse('4.1.5')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_3'),
                version: Version.parse('4.1.4')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.3')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_cmake_path_1')));
        expect(tools.first.version, equals(Version.parse('4.1.3')));
      });

      test('many Android cmake, one system cmake, prefer Android cmake, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_1'),
                version: Version.parse('4.1.2')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_2'),
                version: Version.parse('4.1.5')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_3'),
                version: Version.parse('4.1.4')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.3')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          preferAndroidCmake: true,
          cmakeVersion: "4.1.4"
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_3')));
        expect(tools.first.version, equals(Version.parse('4.1.4')));
      });

      test('many Android cmake, one system cmake, prefer Android cmake, user defined dirty version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_1'),
                version: Version.parse('4.1.2-rc0')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_2'),
                version: Version.parse('4.1.2-rc4')
              ),
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('android_cmake_path_3'),
                version: Version.parse('4.1.4-dirty0')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'CMake'),
                uri: Uri.dataFromString('system_cmake_path_1'),
                version: Version.parse('4.1.3')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          preferAndroidCmake: true,
          cmakeVersion: "4.1.4"
        );
        final tools = await cmake.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_cmake_path_3')));
        expect(tools.first.version, equals(Version.parse('4.1.4-dirty0')));
      });
    });
  });
}
