// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

@TestOn('!browser')
library;

import 'package:native_toolchain_cmake/web.dart';
import 'package:test/test.dart';

void main() {
  test('non-web loader throws UnsupportedError', () {
    expect(
      () => loadEmscriptenModule(scriptUrl: Uri.parse('https://example.com/add.js')),
      throwsUnsupportedError,
    );
  });
}
