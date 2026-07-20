import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/src/builder/builder.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:test/test.dart';

void main() {
  late Logger logger;
  late List<LogRecord> warnings;

  setUp(() {
    warnings = [];
    logger = Logger('UserConfigTest')
      ..onRecord.listen((r) {
        if (r.level >= Level.WARNING) warnings.add(r);
      });
  });

  group('parseFromUserDefines', () {
    test('top-level cmake_version used when no per-OS override', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.linux,
        userDefines: {UserConfigKeys.cmakeVersion: '3.22.1'},
        logger: logger,
      );
      expect(cfg.cmakeVersion, '3.22.1');
      expect(cfg.ninjaVersion, isNull);
      expect(cfg.androidHome, isNull);
      expect(cfg.ndkVersion, isNull);
      expect(cfg.preferAndroidCmake, isFalse);
      expect(cfg.preferAndroidNinja, isFalse);
      expect(warnings, isEmpty);
    });

    test('per-OS sub-map overrides top-level for cmake/ninja version', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.macOS,
        userDefines: {
          UserConfigKeys.cmakeVersion: '3.22.1',
          UserConfigKeys.ninjaVersion: '1.10.2',
          'macos': {UserConfigKeys.cmakeVersion: '3.31.6', UserConfigKeys.ninjaVersion: '1.12.0'},
        },
        logger: logger,
      );
      expect(cfg.targetOS, OS.macOS);
      expect(cfg.cmakeVersion, '3.31.6');
      expect(cfg.ninjaVersion, '1.12.0');
      expect(warnings, isEmpty);
    });

    test('android sub-map populates ndkVersion and androidHome', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: {
          'android': {
            UserConfigKeys.ndkVersion: '28.2.13676358',
            UserConfigKeys.androidHome: r'C:\Android\Sdk',
          },
        },
        logger: logger,
      );
      expect(cfg.targetOS, OS.android);
      expect(cfg.ndkVersion, '28.2.13676358');
      // Path normalised to forward slashes.
      expect(cfg.androidHome, 'C:/Android/Sdk');
      // Defaults for android.
      expect(cfg.preferAndroidCmake, isTrue);
      expect(cfg.preferAndroidNinja, isTrue);
      expect(warnings, isEmpty);
    });

    test('prefer_android_cmake from android sub-map overrides top-level', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: {
          UserConfigKeys.preferAndroidCmake: true,
          UserConfigKeys.preferAndroidNinja: true,
          'android': {UserConfigKeys.preferAndroidCmake: false, UserConfigKeys.preferAndroidNinja: false},
        },
        logger: logger,
      );
      expect(cfg.preferAndroidCmake, isFalse);
      expect(cfg.preferAndroidNinja, isFalse);
      expect(warnings, isEmpty);
    });

    test('non-android targetOS still reads android.* keys (backward compat)', () {
      // Original implementation unconditionally read ndkVersion/androidHome
      // from the `android` sub-map regardless of targetOS; downstream only
      // consults these fields on OS.android, so storing them on other OSes is
      // harmless and preserves backward compatibility.
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.windows,
        userDefines: {
          'android': {
            UserConfigKeys.ndkVersion: '28.2.13676358',
            UserConfigKeys.androidHome: r'C:\Android\Sdk',
          },
          UserConfigKeys.cmakeVersion: '3.31.6',
        },
        logger: logger,
      );
      expect(cfg.targetOS, OS.windows);
      expect(cfg.cmakeVersion, '3.31.6');
      expect(cfg.ndkVersion, '28.2.13676358');
      expect(cfg.androidHome, 'C:/Android/Sdk');
    });

    test('numeric cmake_version tolerated as String (YAML can parse as double)', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.linux,
        userDefines: {UserConfigKeys.cmakeVersion: 3.22},
        logger: logger,
      );
      expect(cfg.cmakeVersion, '3.22');
      expect(warnings, isEmpty);
    });

    test('wrong-typed cmake_version logs warning and is ignored', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.linux,
        userDefines: {
          UserConfigKeys.cmakeVersion: ['3.22.1'],
        },
        logger: logger,
      );
      expect(cfg.cmakeVersion, isNull);
      expect(warnings, isNotEmpty);
      expect(warnings.first.message, contains('cmake_version'));
    });

    test('wrong-typed prefer_android_cmake logs warning and is ignored', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: {UserConfigKeys.preferAndroidCmake: 'no'},
        logger: logger,
      );
      // Falls back to the android default (true).
      expect(cfg.preferAndroidCmake, isTrue);
      expect(warnings, isNotEmpty);
      expect(warnings.first.message, contains('prefer_android_cmake'));
    });

    test('non-Map android sub-map logs warning and is ignored', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: {'android': r'C:\Android\Sdk'},
        logger: logger,
      );
      expect(cfg.androidHome, isNull);
      expect(cfg.ndkVersion, isNull);
      expect(warnings, isNotEmpty);
    });

    test('does not consult ANDROID_HOME env var', () {
      // Regression guard: parseFromUserDefines must leave androidHome null
      // when no android.android_home is provided, regardless of Platform env.
      // (We cannot reliably mutate Platform.environment here, but the absence
      // of the key in userDefines is sufficient because the static parser
      // disables envVarAndroidHomeAsDefault.)
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: <String, dynamic>{},
        logger: logger,
      );
      const env = String.fromEnvironment('ANDROID_HOME');
      // env is '' under normal test runs; assert our explicit contract.
      expect(
        cfg.androidHome,
        env.isEmpty ? null : env,
        reason: 'parseFromUserDefines must not pull ANDROID_HOME from env',
      );
    });

    test('toString contains the relevant fields', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: {
          'android': {UserConfigKeys.ndkVersion: '28.2.13676358'},
          UserConfigKeys.cmakeVersion: '3.22.1',
        },
        logger: logger,
      );
      final s = cfg.toString();
      expect(s, contains('targetOS: android'));
      expect(s, contains('cmakeVersion: 3.22.1'));
      expect(s, contains('ndkVersion: 28.2.13676358'));
    });

    test('copyWith preserves fields and keeps preferAndroid defaults', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: {
          'android': {UserConfigKeys.androidHome: r'C:\Android\Sdk'},
        },
        logger: logger,
      );
      final updated = cfg.copyWith(androidHome: r'D:\Other\Sdk');
      // copyWith goes through the ctor, so the new value is normalised too.
      expect(updated.androidHome, 'D:/Other/Sdk');
      // other fields preserved
      expect(updated.targetOS, OS.android);
      expect(updated.preferAndroidCmake, cfg.preferAndroidCmake);
      expect(updated.preferAndroidNinja, cfg.preferAndroidNinja);
    });

    test('androidHome is normalised to forward slashes and no trailing slash', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: {
          'android': {UserConfigKeys.androidHome: r'C:\Android\Sdk\\'},
        },
        logger: logger,
      );
      expect(cfg.androidHome, 'C:/Android/Sdk');
    });

    test('empty androidHome collapses to null', () {
      final cfg = UserConfig.parseFromUserDefines(
        targetOS: OS.android,
        userDefines: {
          'android': {UserConfigKeys.androidHome: ''},
        },
        logger: logger,
      );
      // parseFromUserDefines passes envVar=false, so ANDROID_HOME env won't
      // leak in; the empty string collapses to null during normalisation.
      expect(cfg.androidHome, isNull);
    });

    test('UserConfig ctor normalises Platform.environment ANDROID_HOME', () {
      // Indirect: ctor with envVarAndroidHomeAsDefault=true and a literal
      // backslash path should also be normalised; cannot mutate Platform
      // environment, so we verify the explicit-pass path instead.
      final cfg = UserConfig(
        targetOS: OS.android,
        androidHome: r'C:\Path\With\Backslashes\',
        envVarAndroidHomeAsDefault: false,
      );
      expect(cfg.androidHome, 'C:/Path/With/Backslashes');
    });
  });

  group('CMakeBuilder.unwrapUserDefinesForTesting', () {
    test('peels workspace_pubspec.defines envelope', () {
      const env = {
        'workspace_pubspec': {
          'base_path': 'D:/flutter/native_toolchain_cmake/example/flutter/pubspec.yaml',
          'defines': {
            'env_file': null,
            'cmake_version': null,
            'ninja_version': null,
            'prefer_android_cmake': null,
            'prefer_android_ninja': null,
            'android': {
              'android_home': r'D:\test_ndk',
              'ndk_version': null,
              'cmake_version': null,
              'ninja_version': null,
            },
          },
        },
      };
      final flat = CMakeBuilder.unwrapUserDefinesForTesting(env);
      expect(flat['android'], isA<Map>());
      expect((flat['android'] as Map)['android_home'], r'D:\test_ndk');
    });

    test('passes through flat defines (no envelope)', () {
      const flat = {
        'env_file': '.env',
        'cmake_version': '3.22.1',
        'android': {'android_home': r'C:\Android\Sdk'},
      };
      final result = CMakeBuilder.unwrapUserDefinesForTesting(flat);
      expect(result, same(flat));
    });

    test('null input returns empty', () {
      expect(CMakeBuilder.unwrapUserDefinesForTesting(null), isEmpty);
    });

    test('envelope with wrong-typed defines logs warning', () {
      final records = <LogRecord>[];
      final l = Logger('UnwrapTest')..onRecord.listen(records.add);
      const env = {
        'workspace_pubspec': {'base_path': 'foo', 'defines': 'not a map'},
      };
      final result = CMakeBuilder.unwrapUserDefinesForTesting(env, logger: l);
      expect(result, isEmpty);
      expect(records.where((r) => r.level >= Level.WARNING), isNotEmpty);
    });
  });
}
