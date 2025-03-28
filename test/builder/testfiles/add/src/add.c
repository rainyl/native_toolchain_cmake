// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "add.h"

int32_t add(int32_t a, int32_t b) {
#ifdef DEBUG
  printf("Adding %i and %i.\n", a, b);
#if _WIN32
  wprintf("Adding %i and %i.\n", a, b);
#endif
#endif
  return a + b;
}
