// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <stdint.h>

#ifdef DEBUG
#include <stdio.h>

#if _WIN32
#include <wchar.h>
#endif
#endif

#if _WIN32
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

FFI_EXPORT int32_t math_add(int32_t a, int32_t b);

#ifdef __cplusplus
}
#endif
