// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:native_toolchain_cmake/src/native_toolchain/android_ndk.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/clang.dart';
import 'package:native_toolchain_cmake/src/tool/tool.dart';
import 'package:native_toolchain_cmake/src/tool/tool_resolver.dart';
import 'package:test/test.dart';

void main() {
  test('cmake with PathToolResolver', () async {
    final resolver = PathToolResolver(toolName: 'cmake', executableName: 'cmake');
    final tools = await resolver.resolve(logger: null);
    expect(tools.length, greaterThan(0));
    expect(await Directory.fromUri(tools.first.uri).exists(), true);
  });

  test('equals and hashCode', () async {
    expect(clang, clang);
    expect(clang != androidNdk, true);
    expect(
      Tool(name: 'foo'),
      Tool(name: 'foo', defaultResolver: PathToolResolver(toolName: 'foo')),
    );
    expect(Tool(name: 'foo') != Tool(name: 'bar'), true);
    expect(
      Tool(name: 'foo').hashCode,
      Tool(name: 'foo', defaultResolver: PathToolResolver(toolName: 'foo')).hashCode,
    );
    expect(Tool(name: 'foo').hashCode != Tool(name: 'bar').hashCode, true);
  });
}
