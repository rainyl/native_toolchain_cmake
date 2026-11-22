// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'package:add/src/g/add.g.dart';

int calculate(int a, int b, {int times = 1}) {
  final result = math_add(a, b);
  return result * times;
}

/// Native builds do not need an explicit initialization step.
Future<void> initAdd({Uri? scriptUrl, List<int>? wasmBinary}) async {}
