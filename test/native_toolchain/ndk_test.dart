// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_cmake/src/builder/user_config.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/android_ndk.dart';
import 'package:native_toolchain_cmake/src/tool/tool_requirement.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Creates the minimal on-disk layout needed to pass `_validSdkDirectory`.
///
/// Returns the [Directory] backing [uri].
Future<Directory> _createFakeSdk(Uri uri) async {
  final dir = await Directory.fromUri(uri).create(recursive: true);
  await Directory.fromUri(uri.resolve('platform-tools/')).create();
  return dir;
}

/// Creates a fake NDK version directory under [sdkUri]/ndk/.
Future<Directory> _createFakeNdk(Uri sdkUri, String version) async {
  final ndkDir = Directory.fromUri(sdkUri.resolve('ndk/').resolve('$version/'));
  await ndkDir.create(recursive: true);
  await Directory.fromUri(ndkDir.uri.resolve('toolchains/llvm/prebuilt/')).create(recursive: true);
  return ndkDir;
}

void main() {
  test('NDK smoke test', () async {
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

  // Regression test for https://github.com/rainyl/native_toolchain_cmake/issues/37
  //
  // `package:glob` treats `\` as an escape character rather than a path
  // separator, so a Windows `androidHome` such as `C:\Android\Sdk` would be
  // fed into `Glob('$androidHome/ndk/*/')` and silently match nothing. The
  // fix normalises backslashes to forward slashes at [UserConfig] construction
  // time. This test reproduces the original failure mode by feeding a real
  // on-disk SDK tree via a backslash-laden path (on Windows) or a
  // forward-slash path (other OSes), then asserts the NDK is discovered.
  test('issue-37-windows-backslash', () async {
    final tempUri = await tempDirForTest();
    final sdkDir = await _createFakeSdk(tempUri.resolve('android_sdk/'));

    const ndkVersion = '99.99.99999';
    await _createFakeNdk(sdkDir.uri, ndkVersion);

    final rawAndroidHome = sdkDir.absolute.path;
    expect(
      UserConfig(targetOS: OS.android, androidHome: rawAndroidHome).androidHome,
      rawAndroidHome.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), ''),
      reason: 'UserConfig must normalise backslashes to forward slashes',
    );

    final userConfig = UserConfig(
      targetOS: OS.android,
      androidHome: rawAndroidHome,
      ndkVersion: ndkVersion,
      envVarAndroidHomeAsDefault: false,
    );

    final resolved = await androidNdk.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

    final ndkInstances = resolved.where((t) => t.tool == androidNdk).toList();
    expect(ndkInstances, hasLength(1), reason: 'Only the fixture NDK should match ndkVersion filter');
    expect(
      ndkInstances.single.uri.toFilePath().replaceAll(r'\', '/'),
      contains('/ndk/$ndkVersion/'),
      reason: 'Resolved NDK URI must point at the fixture we created',
    );
  });

  test('env var ANDROID_NDK_HOME is highest priority', () async {
    final tempUri = await tempDirForTest();
    final ndkDir = await _createFakeNdk(tempUri.resolve('custom_sdk/'), '99.99.99999');

    final environment = {kAndroidNdkHome: ndkDir.absolute.path};
    final userConfig = UserConfig(
      targetOS: OS.android,
      ndkVersion: '99.99.99999',
      envVarAndroidHomeAsDefault: false,
    );

    final resolved = await androidNdk.defaultResolver!.resolve(
      logger: logger,
      userConfig: userConfig,
      environment: environment,
    );

    final ndkInstances = resolved.where((t) => t.tool == androidNdk).toList();
    expect(ndkInstances, isNotEmpty, reason: 'NDK must be found via ANDROID_NDK_HOME');
    expect(
      ndkInstances.first.uri.toFilePath().replaceAll(r'\', '/'),
      ndkDir.absolute.uri.toFilePath().replaceAll(r'\', '/'),
    );
  });

  test('ndkVersion filter skips env-var roots without parseable basename', () async {
    final tempUri = await tempDirForTest();
    // Give the NDK root a non-parseable name, e.g. not a Version.
    final ndkRoot = await Directory.fromUri(tempUri.resolve('my_ndk_dir/')).create(recursive: true);

    final environment = {kAndroidNdkHome: ndkRoot.absolute.path};
    final userConfig = UserConfig(
      targetOS: OS.android,
      ndkVersion: '99.99.99999',
      envVarAndroidHomeAsDefault: false,
    );

    // Skipping to avoid spamming logger output in the test.
    // Expect an exception, as no candidate's basename matches 99.99.99999.
    expect(
      () => androidNdk.defaultResolver!.resolve(
        logger: logger,
        userConfig: userConfig,
        environment: environment,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('dir/sdk fallback when androidHome points at parent', () async {
    final tempUri = await tempDirForTest();
    // Layout: <home>/sdk/ is the actual SDK.
    // <home>/ itself does NOT contain platform-tools.
    final sdkDir = await _createFakeSdk(tempUri.resolve('home/sdk/'));
    await _createFakeNdk(sdkDir.uri, '99.99.99999');

    // Point androidHome at <home> (not <home>/sdk).
    final homeDir = Directory.fromUri(tempUri.resolve('home/'));

    final userConfig = UserConfig(
      targetOS: OS.android,
      androidHome: homeDir.absolute.path,
      ndkVersion: '99.99.99999',
      envVarAndroidHomeAsDefault: false,
    );

    final resolved = await androidNdk.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

    final ndkInstances = resolved.where((t) => t.tool == androidNdk).toList();
    expect(ndkInstances, hasLength(1), reason: 'NDK must be found via <home>/sdk fallback');
    expect(
      ndkInstances.single.uri.toFilePath().replaceAll(r'\', '/'),
      contains('/sdk/ndk/99.99.99999/'),
    );
  });

  test('ANDROID_NDK_HOME is skipped when nonexistent, falls through to platform', () async {
    final tempUri = await tempDirForTest();
    final sdkDir = await _createFakeSdk(tempUri.resolve('android_sdk/'));
    await _createFakeNdk(sdkDir.uri, '99.99.99999');

    // ANDROID_NDK_HOME points to a non-existent directory; this should be
    // ignored with a warning, and the platform-default discovery should still
    // find the real SDK (or the fixture if ANDROID_HOME is set to it).
    final environment = {
      kAndroidNdkHome: tempUri.resolve('does_not_exist/').toFilePath(),
      kAndroidHome: sdkDir.absolute.path,
    };
    final userConfig = UserConfig(
      targetOS: OS.android,
      ndkVersion: '99.99.99999',
      envVarAndroidHomeAsDefault: false,
    );

    final resolved = await androidNdk.defaultResolver!.resolve(
      logger: logger,
      userConfig: userConfig,
      environment: environment,
    );

    final ndkInstances = resolved.where((t) => t.tool == androidNdk).toList();
    expect(ndkInstances, hasLength(1), reason: 'Should fall through to ANDROID_HOME');
    expect(
      ndkInstances.single.uri.toFilePath().replaceAll(r'\', '/'),
      contains('/ndk/99.99.99999/'),
    );
  });
}
