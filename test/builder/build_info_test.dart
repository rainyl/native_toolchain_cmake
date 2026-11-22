// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('CMakeBuildInfo round trip', () async {
    final tempUri = await tempDirForTest();
    final info = CMakeBuildInfo(
      buildDir: tempUri.resolve('build/'),
      installDir: tempUri.resolve('build/install/'),
      buildMode: 'Release',
    );
    await info.write(directory: info.installDir, name: 'foo');

    final read = await CMakeBuildInfo.read(artifact: info.installDir.resolve('lib/libfoo.a'), name: 'foo');
    expect(read, isNotNull);
    expect(read!.buildDir, info.buildDir);
    expect(read.installDir, info.installDir);
    expect(read.buildMode, 'Release');
  });

  test('CMakeBuildInfo is found from a nested artifact', () async {
    final tempUri = await tempDirForTest();
    final info = CMakeBuildInfo(
      buildDir: tempUri,
      installDir: tempUri.resolve('install/'),
      buildMode: 'Debug',
    );
    await info.write(directory: info.installDir, name: 'foo');

    final read = await CMakeBuildInfo.read(
      artifact: info.installDir.resolve('lib/deep/libfoo.a'),
      name: 'foo',
    );
    expect(read?.buildMode, 'Debug');
  });

  test('CMakeBuildInfo of another install prefix is ignored', () async {
    final tempUri = await tempDirForTest();
    final other = await tempDirForTest();
    final info = CMakeBuildInfo(buildDir: tempUri, installDir: other, buildMode: 'Release');
    await info.write(directory: tempUri.resolve('install/'), name: 'foo');

    final read = await CMakeBuildInfo.read(artifact: tempUri.resolve('install/lib/libfoo.a'), name: 'foo');
    expect(read, isNull, reason: 'the record belongs to a different install prefix');
  });

  test('CMakeBuildInfo.read returns null without a record', () async {
    final tempUri = await tempDirForTest();
    final read = await CMakeBuildInfo.read(artifact: tempUri.resolve('libfoo.a'), name: 'foo');
    expect(read, isNull);
  });

  test('CMakeBuildInfo.read ignores a malformed record', () async {
    final tempUri = await tempDirForTest();
    await File.fromUri(tempUri.resolve(cmakeBuildInfoFileNameFor('foo'))).writeAsString('{not json');
    final read = await CMakeBuildInfo.read(artifact: tempUri.resolve('libfoo.a'), name: 'foo');
    expect(read, isNull);
  });

  test('records of different libraries do not collide', () async {
    final tempUri = await tempDirForTest();
    final installDir = tempUri.resolve('install/');
    final first = CMakeBuildInfo(
      buildDir: tempUri.resolve('build-a/'),
      installDir: installDir,
      buildMode: 'Release',
    );
    final second = CMakeBuildInfo(
      buildDir: tempUri.resolve('build-b/'),
      installDir: installDir,
      buildMode: 'Debug',
    );
    await first.write(directory: installDir, name: 'foo');
    await second.write(directory: installDir, name: 'bar');

    expect(cmakeBuildInfoFileNameFor('foo'), isNot(cmakeBuildInfoFileNameFor('bar')));
    expect(
      (await CMakeBuildInfo.read(artifact: installDir.resolve('lib/libfoo.a'), name: 'foo'))?.buildDir,
      first.buildDir,
    );
    expect(
      (await CMakeBuildInfo.read(artifact: installDir.resolve('lib/libbar.a'), name: 'bar'))?.buildDir,
      second.buildDir,
    );
  });

  test('CMakeBuildInfo json', () {
    final info = CMakeBuildInfo(
      buildDir: Uri.directory('/tmp/build'),
      installDir: Uri.directory('/tmp/build/install'),
      buildMode: 'release',
    );
    final decoded = CMakeBuildInfo.tryParse(jsonDecode(jsonEncode(info.toJson())));
    expect(decoded?.buildDir, info.buildDir);
    expect(decoded?.installDir, info.installDir);
    expect(decoded?.buildMode, info.buildMode);
  });

  test('CMakeBuildInfo.tryParse rejects incomplete records', () {
    expect(CMakeBuildInfo.tryParse({'build_mode': 'release'}), isNull);
    expect(CMakeBuildInfo.tryParse({'build_dir': '/a', 'install_dir': '/a'}), isNull);
    expect(CMakeBuildInfo.tryParse({'build_dir': 1, 'install_dir': '/a', 'build_mode': 'release'}), isNull);
    expect(CMakeBuildInfo.tryParse(const []), isNull);
    expect(CMakeBuildInfo.tryParse(null), isNull);
  });

  test('CMakeBuildInfo.read skips a record without the expected fields', () async {
    final tempUri = await tempDirForTest();
    final installDir = tempUri.resolve('install/');
    await File.fromUri(installDir.resolve(cmakeBuildInfoFileNameFor('foo'))).create(recursive: true);
    await File.fromUri(
      installDir.resolve(cmakeBuildInfoFileNameFor('foo')),
    ).writeAsString('{"build_mode":"release"}');

    expect(await CMakeBuildInfo.read(artifact: installDir.resolve('lib/libfoo.a'), name: 'foo'), isNull);
  });

  test('keepSymbolsFileUri and treeshakeStageDirectory', () {
    final info = CMakeBuildInfo(
      buildDir: Uri.directory('/tmp/build'),
      installDir: Uri.directory('/tmp/build/install'),
      buildMode: 'release',
    );
    expect(info.keepSymbolsFileUri('foo').toFilePath(), '/tmp/build/dntcm_keep_symbols_foo.txt');
    expect(info.treeshakeStageDirectory.toFilePath(), '/tmp/build/dntcm_treeshake/');
  });

  test('the file names match cmake/treeshake.cmake', () async {
    final module = File.fromUri((await dntcmCmakeDir()).resolve('treeshake.cmake')).readAsStringSync();
    // Both sides spell the names out, so assert the spellings, not just the prefix:
    // a rename on one side must fail here instead of at configure time.
    expect(cmakeTreeshakeStageDirName, 'dntcm_treeshake');
    expect(module, contains('"\${CMAKE_BINARY_DIR}/dntcm_treeshake"'));
    expect(module, contains('\${CMAKE_BINARY_DIR}/dntcm_keep_symbols_\${_output_name}.txt'));
    expect(module, contains('DNTCM_CMAKE_DIR'));
    expect(cmakeKeepSymbolsFileNameFor('foo'), 'dntcm_keep_symbols_foo.txt');
    expect(cmakeBuildInfoFileNameFor('foo'), 'dntcm_build_info_foo.json');
    expect(cmakeKeepSymbolsFileNameFor('foo'), isNot(cmakeKeepSymbolsFileNameFor('bar')));
  });
}
