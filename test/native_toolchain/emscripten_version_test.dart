// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'package:native_toolchain_cmake/src/native_toolchain/emscripten.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('requires Emscripten 6.0.0 or newer', () {
    expect(isSupportedEmscriptenVersion(null), isFalse);
    expect(isSupportedEmscriptenVersion(Version.parse('3.1.51')), isFalse);
    expect(isSupportedEmscriptenVersion(Version.parse('5.0.0')), isFalse);
    expect(isSupportedEmscriptenVersion(Version.parse('6.0.0')), isTrue);
    expect(isSupportedEmscriptenVersion(Version.parse('6.0.0-git')), isTrue);
    expect(isSupportedEmscriptenVersion(Version.parse('7.0.0-git')), isTrue);
  });
}
