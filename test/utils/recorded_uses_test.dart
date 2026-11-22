// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

void main() {
  test('symbolsFromFunctionNames keeps the names as-is', () {
    expect(symbolsFromFunctionNames(['cv_add', 'cv_sub']), ['cv_add', 'cv_sub']);
  });

  test('symbolsFromFunctionNames applies the record-use mapping', () {
    expect(symbolsFromFunctionNames(['add', 'sub', 'mul'], mapping: {'add': 'cv_add', 'sub': 'cv_sub'}), [
      'cv_add',
      'cv_sub',
      'mul',
    ]);
  });

  test('symbolsFromFunctionNames of nothing is empty', () {
    expect(symbolsFromFunctionNames(const []), isEmpty);
  });
}
