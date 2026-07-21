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
    // Build a fake SDK layout: <sdk>/ndk/<version>/
    final tempUri = await tempDirForTest();
    final sdkDir = await Directory.fromUri(tempUri.resolve("android_sdk")).create(recursive: true);

    // Use an obviously-fake, very-high version so this fixture never collides
    // with any real NDK installed under $HOME/AppData/Local/Android/Sdk (which
    // the resolver also searches on Windows regardless of androidHome).
    const ndkVersion = '99.99.99999';
    final ndkDir = Directory.fromUri(sdkDir.uri.resolve('ndk/').resolve('$ndkVersion/'));
    await ndkDir.create(recursive: true);
    // tryResolveClang lists `toolchains/llvm/prebuilt/`; create it empty so
    // the resolver returns no clang/ar/lld instances without throwing.
    await Directory.fromUri(ndkDir.uri.resolve('toolchains/llvm/prebuilt/')).create(recursive: true);

    // Use the OS-native path which on Windows contains backslashes; on
    // other platforms it is already forward-slash. Either way the test must
    // pass, demonstrating that UserConfig normalisation keeps the glob
    // pattern valid.
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

    // If the androidHome backslashes are NOT normalised before being fed to
    // `Glob('<androidHome>/ndk/*/')` package:glob treats `\` as an escape and
    // the pattern matches nothing under our fixture, so the resolver cannot
    // find an NDK with the requested version and throws.
    final resolved = await androidNdk.defaultResolver!.resolve(logger: logger, userConfig: userConfig);

    final ndkInstances = resolved.where((t) => t.tool == androidNdk).toList();
    expect(ndkInstances, hasLength(1), reason: 'Only the fixture NDK should match ndkVersion filter');
    expect(
      ndkInstances.single.uri.toFilePath().replaceAll(r'\', '/'),
      contains('/ndk/$ndkVersion/'),
      reason: 'Resolved NDK URI must point at the fixture we created',
    );
  });
}
