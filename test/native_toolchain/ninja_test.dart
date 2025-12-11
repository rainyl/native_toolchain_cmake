import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:mocktail/mocktail.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/ninja.dart';
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
      unitTestNinjaSystemResolver = mockSystemResolver;
      pathsSearched.clear();
      InstallLocationResolver.unitTestTryResolvePath = mockTryResolvePath;
    });

    test('Android home not set', () async {
      when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => [
            ToolInstance(
              tool: Tool(name: 'Ninja'),
              uri: Uri.dataFromString('system_ninja_path_1'),
              version: Version.parse('1.12.1')
            ),
          ]));
      final userConfig = UserConfig(
        targetOS: OS.android,
        envVarAndroidHomeAsDefault: false,
      );

      final executableName = OS.current.executableFileName('ninja');
      String expectedSearchPath = executableName;
      if (Platform.isLinux) {
        expectedSearchPath = r'$HOME/Android/Sdk/cmake/*/bin/' + expectedSearchPath;
      } else if (Platform.isMacOS) {
        expectedSearchPath = r'$HOME/Library/Android/sdk/cmake/*/bin/' + expectedSearchPath;
      } else if (Platform.isWindows) {
        expectedSearchPath = r'$HOME/AppData/Local/Android/Sdk/cmake/*/bin/' + expectedSearchPath;
      }
      
      final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

      expect(pathsSearched.length, equals(1));
      expect(pathsSearched.first, equals(expectedSearchPath));
      expect(tools.length, equals(1));
      expect(tools.first.uri, equals(Uri.dataFromString('system_ninja_path_1')));
      expect(tools.first.version, equals(Version.parse('1.12.1')));
    });

    test('Android home is set', () async {
      when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
          .thenAnswer((_) => Future<List<ToolInstance>>(() => [
            ToolInstance(
              tool: Tool(name: 'Ninja'),
              uri: Uri.dataFromString('system_ninja_path_1'),
              version: Version.parse('1.12.1')
            ),
          ]));
      final userConfig = UserConfig(
        targetOS: OS.android,
        envVarAndroidHomeAsDefault: false,
        androidHome: 'my/android/home',
      );

      final executableName = OS.current.executableFileName('ninja');
      String expectedSearchPath = executableName;
      if (Platform.isLinux) {
        expectedSearchPath = r'$HOME/Android/Sdk/cmake/*/bin/' + expectedSearchPath;
      } else if (Platform.isMacOS) {
        expectedSearchPath = r'$HOME/Library/Android/sdk/cmake/*/bin/' + expectedSearchPath;
      } else if (Platform.isWindows) {
        expectedSearchPath = r'$HOME/AppData/Local/Android/Sdk/cmake/*/bin/' + expectedSearchPath;
      }
      
      final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

      expect(pathsSearched.length, equals(2));
      expect(pathsSearched.first, equals('my/android/home/cmake/*/bin/$executableName'));
      expect(pathsSearched[1], equals(expectedSearchPath));
      expect(tools.length, equals(1));
      expect(tools.first.uri, equals(Uri.dataFromString('system_ninja_path_1')));
      expect(tools.first.version, equals(Version.parse('1.12.1')));
    });
  });

  group('Ninja selection: ', () {
    setUp(() {
      mockAndroidResolver = MockCliVersionResolver();
      mockSystemResolver = MockCliVersionResolver();
      unitTestNinjaAndroidResolver = mockAndroidResolver;
      unitTestNinjaSystemResolver = mockSystemResolver;
    });

    group('Android target: ', () {
      test('one Android ninja, any version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.android,
          envVarAndroidHomeAsDefault: false,
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.12.1')));
      });

      test('many Android ninja, latest version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.2')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_2'),
                version: Version.parse('1.13.1')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_3'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.android,
          envVarAndroidHomeAsDefault: false,
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(3));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_2')));
        expect(tools.first.version, equals(Version.parse('1.13.1')));
      });

      test('many Android ninja, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.13.2')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_2'),
                version: Version.parse('1.12.1')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_3'),
                version: Version.parse('1.11.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.android,
          envVarAndroidHomeAsDefault: false,
          ninjaVersion: '1.11.1',
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_3')));
        expect(tools.first.version, equals(Version.parse('1.11.1')));
      });

      test('one Android ninja, no system ninja, prefers system ninja', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.android,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: false,
        );

        expect(() async => ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig), throwsA(isA<Exception>()));
      });

      test('no Android ninja, has system ninja', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.android,
          envVarAndroidHomeAsDefault: false,
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.12.1')));
      });

      test('no Android ninja, has system ninja, prefers Android ninja', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.android,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: true,
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.12.1')));
      });

      test('many Android ninja, has system ninja, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.13.2')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_2'),
                version: Version.parse('1.12.2')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_3'),
                version: Version.parse('1.10.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.android,
          envVarAndroidHomeAsDefault: false,
          ninjaVersion: "1.12.1"
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.12.1')));
      });
    });

    group('iOS target: ', () {
      test('one Android ninja, no system ninja', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
        );

        expect(() async => ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig), throwsA(isA<Exception>()));
      });

      test('one Android ninja, no system ninja, do not prefer Android ninja', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: false,
        );

        expect(() async => ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig), throwsA(isA<Exception>()));
      });

      test('one Android ninja, no system ninja, prefer Android ninja, any version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: true,
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.12.1')));
      });

      test('one Android ninja, no system ninja, prefer Android ninja, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: true,
          ninjaVersion: "1.12.1",
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.12.1')));
      });

      test('one Android ninja, no system ninja, prefer Android ninja, user defined version not found', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => []));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: true,
          ninjaVersion: "1.12.3",
        );
        expect(() async => ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig), throwsA(isA<Exception>()));
      });

      test('one Android ninja, one system ninja, do not prefer Android ninja, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          ninjaVersion: "1.12.1",
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.12.1')));
      });

      test('one Android ninja, one system ninja, prefer Android ninja, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: true,
          ninjaVersion: "1.12.1",
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(2));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.12.1')));
      });

      test('many Android ninja, one system ninja, prefer Android ninja, latest version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_2'),
                version: Version.parse('1.15.5')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_3'),
                version: Version.parse('1.14.4')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.13.3')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: true,
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(4));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_2')));
        expect(tools.first.version, equals(Version.parse('1.15.5')));
      });

      test('many Android ninja, one system ninja, do not prefer Android ninja, latest version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_2'),
                version: Version.parse('1.15.5')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_3'),
                version: Version.parse('1.11.4')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.13.3')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('system_ninja_path_1')));
        expect(tools.first.version, equals(Version.parse('1.13.3')));
      });

      test('many Android ninja, one system ninja, prefer Android ninja, user defined version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_2'),
                version: Version.parse('1.14.5')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_3'),
                version: Version.parse('1.14.4')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.14.3')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: true,
          ninjaVersion: "1.14.4"
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_3')));
        expect(tools.first.version, equals(Version.parse('1.14.4')));
      });

      test('many Android ninja, one system ninja, prefer Android ninja, user defined dirty version', () async {
        when(() => mockAndroidResolver.resolve(logger: any(named: 'logger'), userConfig: any(named: 'userConfig')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_1'),
                version: Version.parse('1.12.1-rc0')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_2'),
                version: Version.parse('1.12.1-rc4')
              ),
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('android_ninja_path_3'),
                version: Version.parse('1.14.4-dirty0')
              ),
            ]));
        when(() => mockSystemResolver.resolve(logger: any(named: 'logger')))
            .thenAnswer((_) => Future<List<ToolInstance>>(() => [
              ToolInstance(
                tool: Tool(name: 'Ninja'),
                uri: Uri.dataFromString('system_ninja_path_1'),
                version: Version.parse('1.13.3')
              ),
            ]));
        final userConfig = UserConfig(
          targetOS: OS.iOS,
          envVarAndroidHomeAsDefault: false,
          preferAndroidNinja: true,
          ninjaVersion: "1.14.4"
        );
        final tools = await ninja.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

        expect(tools.length, equals(1));
        expect(tools.first.uri, equals(Uri.dataFromString('android_ninja_path_3')));
        expect(tools.first.version, equals(Version.parse('1.14.4-dirty0')));
      });
    });
  });
}
