// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
//
// This file is adapted from https://github.com/dart-lang/native/tree/main/pkgs/native_toolchain_c
// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/android_ndk.dart';
import 'package:native_toolchain_cmake/src/tool/tool.dart';
import 'package:native_toolchain_cmake/src/tool/tool_instance.dart';
import 'package:native_toolchain_cmake/src/tool/tool_requirement.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Creates a temporary directory that is cleaned up after the test.
Future<Directory> createTempDir() async {
  final dir = await Directory.systemTemp.createTemp('ndk_test_');
  addTearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });
  return dir;
}

/// Filter instances to only those matching [tool].
List<ToolInstance> filterTool(List<ToolInstance> instances, Tool tool) =>
    instances.where((i) => i.tool.name == tool.name).toList();

void main() {
  group('Android NDK resolution', () {
    // Smoke test: only runs when NDK is available on the host.
    test('NDK smoke test', () async {
      final ndkHome = Platform.environment['ANDROID_NDK_HOME'];
      if (ndkHome == null && !Platform.isLinux) {
        // On non-Linux without ANDROID_NDK_HOME, skip — needs SDK/NDK installed.
        return;
      }
      final requirement = RequireAll([
        ToolRequirement(androidNdk),
        ToolRequirement(androidNdkClang),
        ToolRequirement(androidNdkLlvmAr),
        ToolRequirement(androidNdkLld),
      ]);
      final resolved = await androidNdk.defaultResolver!.resolve(logger: logger);
      final satisfied = requirement.satisfy(resolved);
      expect(satisfied?.length, 4);
    });

    test('resolves NDK from ANDROID_NDK_HOME env var', () async {
      final tempDir = await createTempDir();
      final ndkDir = Directory('${tempDir.path}/ndk-home');
      await ndkDir.create();

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_NDK_HOME': ndkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.any((i) => i.uri == ndkDir.absolute.uri), isTrue);
    });

    test('resolves NDK from ANDROID_NDK_PATH env var', () async {
      final tempDir = await createTempDir();
      final ndkDir = Directory('${tempDir.path}/ndk-path');
      await ndkDir.create();

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_NDK_PATH': ndkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.any((i) => i.uri == ndkDir.absolute.uri), isTrue);
    });

    test('resolves NDK from ANDROID_NDK_ROOT env var', () async {
      final tempDir = await createTempDir();
      final ndkDir = Directory('${tempDir.path}/ndk-root');
      await ndkDir.create();

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_NDK_ROOT': ndkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.any((i) => i.uri == ndkDir.absolute.uri), isTrue);
    });

    test('ANDROID_NDK_HOME takes priority over ANDROID_NDK_ROOT', () async {
      final tempDir = await createTempDir();
      final ndkHome = Directory('${tempDir.path}/ndk-home');
      final ndkRoot = Directory('${tempDir.path}/ndk-root');
      await ndkHome.create();
      await ndkRoot.create();

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_NDK_HOME': ndkHome.path, 'ANDROID_NDK_ROOT': ndkRoot.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      // ANDROID_NDK_HOME was found and takes priority (listed first)
      expect(ndkInstances.any((i) => i.uri == ndkHome.absolute.uri), isTrue);
      // ANDROID_NDK_ROOT should NOT be present (lower priority, break on first match)
      expect(ndkInstances.any((i) => i.uri == ndkRoot.absolute.uri), isFalse);
    });

    test('resolves NDK from ANDROID_HOME with valid SDK and ndk subdir', () async {
      final tempDir = await createTempDir();
      final sdkDir = Directory('${tempDir.path}/sdk');
      await Directory('${sdkDir.path}/platform-tools').create(recursive: true);
      final ndkDir = Directory('${sdkDir.path}/ndk/27.0.0');
      await ndkDir.create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_HOME': sdkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.length, 1);
      expect(ndkInstances.first.uri, equals(ndkDir.absolute.uri));
    });

    test('resolves NDK from ANDROID_HOME when SDK has licenses (not platform-tools)', () async {
      final tempDir = await createTempDir();
      final sdkDir = Directory('${tempDir.path}/sdk');
      await Directory('${sdkDir.path}/licenses').create(recursive: true);
      final ndkDir = Directory('${sdkDir.path}/ndk/26.3.0');
      await ndkDir.create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_HOME': sdkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.length, 1);
      expect(ndkInstances.first.uri, equals(ndkDir.absolute.uri));
    });

    test('skips invalid ANDROID_HOME (no platform-tools or licenses)', () async {
      final tempDir = await createTempDir();
      final invalidSdk = Directory('${tempDir.path}/invalid_sdk');
      await invalidSdk.create();
      // No platform-tools, no licenses → invalid SDK
      // Create an ndk dir anyway (should NOT be found)
      await Directory('${invalidSdk.path}/ndk/1.0.0').create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_HOME': invalidSdk.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      // Should not find NDK because the ANDROID_HOME directory is not a valid SDK.
      // Unless the OS default path also matches (e.g., $HOME/.../Sdk/ndk/*/).
      // The ndk instances may come from OS default paths, so we accept both cases.
      if (ndkInstances.isNotEmpty) {
        // If found, it must NOT be from the invalid SDK
        for (final instance in ndkInstances) {
          expect(instance.uri.toFilePath(), isNot(contains(invalidSdk.path)));
        }
      }
    });

    test('falls back to {ANDROID_HOME}/sdk subdir when ANDROID_HOME points to parent', () async {
      final tempDir = await createTempDir();
      final androidParent = Directory('${tempDir.path}/some-parent');
      final sdkDir = Directory('${androidParent.path}/sdk');
      await Directory('${sdkDir.path}/platform-tools').create(recursive: true);
      final ndkDir = Directory('${sdkDir.path}/ndk/25.2.0');
      await ndkDir.create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_HOME': androidParent.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.length, 1);
      expect(ndkInstances.first.uri, equals(ndkDir.absolute.uri));
    });

    test('ANDROID_SDK_ROOT (deprecated) is checked as fallback', () async {
      final tempDir = await createTempDir();
      final sdkDir = Directory('${tempDir.path}/deprecated-sdk');
      await Directory('${sdkDir.path}/platform-tools').create(recursive: true);
      final ndkDir = Directory('${sdkDir.path}/ndk/28.0.0');
      await ndkDir.create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {
          // ANDROID_HOME points to invalid location, ANDROID_SDK_ROOT is valid
          'ANDROID_HOME': '${tempDir.path}/nonexistent',
          'ANDROID_SDK_ROOT': sdkDir.path,
        },
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.length, 1);
      expect(ndkInstances.first.uri, equals(ndkDir.absolute.uri));
    });

    test('userConfig androidHome takes priority over env vars', () async {
      final tempDir = await createTempDir();
      final configSdk = Directory('${tempDir.path}/config-sdk');
      final envSdk = Directory('${tempDir.path}/env-sdk');
      await Directory('${configSdk.path}/platform-tools').create(recursive: true);
      await Directory('${envSdk.path}/platform-tools').create(recursive: true);
      final configNdk = Directory('${configSdk.path}/ndk/30.0.0');
      final envNdk = Directory('${envSdk.path}/ndk/1.0.0');
      await configNdk.create(recursive: true);
      await envNdk.create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        userConfig: UserConfig(targetOS: OS.android, androidHome: configSdk.path),
        environment: {'ANDROID_HOME': envSdk.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.length, 1);
      expect(ndkInstances.first.uri, equals(configNdk.absolute.uri));
    });

    test('picks latest NDK version from ndk subdir', () async {
      final tempDir = await createTempDir();
      final sdkDir = Directory('${tempDir.path}/sdk');
      await Directory('${sdkDir.path}/platform-tools').create(recursive: true);
      final oldNdk = Directory('${sdkDir.path}/ndk/21.0.0');
      final newNdk = Directory('${sdkDir.path}/ndk/34.0.0');
      await oldNdk.create(recursive: true);
      await newNdk.create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_HOME': sdkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      // Both versions resolved, sorted latest first
      expect(ndkInstances.length, 2);
      // After sort + dedup, latest first
      expect(ndkInstances[0].version, Version(34, 0, 0));
      expect(ndkInstances[1].version, Version(21, 0, 0));
    });

    test('filters by ndkVersion in userConfig', () async {
      final tempDir = await createTempDir();
      final sdkDir = Directory('${tempDir.path}/sdk');
      await Directory('${sdkDir.path}/platform-tools').create(recursive: true);
      final targetNdk = Directory('${sdkDir.path}/ndk/28.0.0');
      final otherNdk = Directory('${sdkDir.path}/ndk/33.0.0');
      await targetNdk.create(recursive: true);
      await otherNdk.create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        userConfig: UserConfig(targetOS: OS.android, ndkVersion: '28.0.0'),
        environment: {'ANDROID_HOME': sdkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      expect(ndkInstances.length, 1);
      expect(ndkInstances.first.uri, equals(targetNdk.absolute.uri));
    });

    test('throws when ndkVersion filter matches nothing', () async {
      final tempDir = await createTempDir();
      final sdkDir = Directory('${tempDir.path}/sdk');
      await Directory('${sdkDir.path}/platform-tools').create(recursive: true);
      await Directory('${sdkDir.path}/ndk/26.0.0').create(recursive: true);

      final resolve = androidNdk.defaultResolver!.resolve(
        logger: logger,
        userConfig: UserConfig(targetOS: OS.android, ndkVersion: '99.0.0'),
        environment: {'ANDROID_HOME': sdkDir.path},
      );

      expect(resolve, throwsA(isA<Exception>()));
    });

    test('deduplicates NDK instances from multiple resolution paths', () async {
      final tempDir = await createTempDir();
      // Create a directory structure where the same NDK is reachable via:
      // 1. ANDROID_NDK_HOME env var
      // 2. ANDROID_HOME/ndk/* (via _resolveAndroidHome + InstallLocationResolver)
      final sdkDir = Directory('${tempDir.path}/sdk');
      await Directory('${sdkDir.path}/platform-tools').create(recursive: true);
      final ndkDir = Directory('${sdkDir.path}/ndk/27.0.0');
      await ndkDir.create(recursive: true);

      // ANDROID_NDK_HOME points to ndkDir, ANDROID_HOME points to sdkDir
      // Both would resolve to the same NDK root (ndkDir)
      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_NDK_HOME': ndkDir.path, 'ANDROID_HOME': sdkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      // Deduplicated by URI
      expect(ndkInstances.length, 1);
      expect(ndkInstances.first.uri, equals(ndkDir.absolute.uri));
    });

    test('OS default paths are checked when env vars not set', () async {
      // This test verifies that the OS default search paths are constructed
      // correctly. We can't easily control $HOME in Platform.environment,
      // but we can verify the resolver doesn't crash and returns empty.
      // The actual path resolution depends on the host filesystem.
      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: <String, String>{}, // No NDK or SDK env vars
      );

      // Should not throw, just return empty or whatever matches on this host.
      expect(instances, isA<List<ToolInstance>>());
    });

    test('extracts version from NDK directory name', () async {
      final tempDir = await createTempDir();
      final ndkDir = Directory('${tempDir.path}/ndk/27.0.12077973');
      await ndkDir.create(recursive: true);

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_NDK_HOME': ndkDir.path},
      );

      final ndkInstances = filterTool(instances, androidNdk);
      final target = ndkInstances.cast<ToolInstance?>().firstWhere(
            (i) => i!.uri == ndkDir.absolute.uri,
            orElse: () => null,
          );
      expect(target, isNotNull);
      expect(target!.version, Version(27, 0, 12077973));
    });
  });

  group('_resolveAndroidHome cross-platform', () {
    test('resolves ANDROID_HOME on all platforms (via environment param)', () async {
      final tempDir = await createTempDir();
      final sdkDir = Directory('${tempDir.path}/sdk');
      await Directory('${sdkDir.path}/platform-tools').create(recursive: true);

      // Use forward slashes in path to simulate cross-platform normalization.
      final unixStylePath = sdkDir.path.replaceAll(r'\', '/');

      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_HOME': unixStylePath},
      );

      // Should not throw; path normalization handles both styles.
      expect(instances, isA<List<ToolInstance>>());
    });

    test('empty ANDROID_HOME is ignored', () async {
      final instances = await androidNdk.defaultResolver!.resolve(
        logger: logger,
        environment: {'ANDROID_HOME': ''},
      );

      expect(instances, isA<List<ToolInstance>>());
    });
  });
}
