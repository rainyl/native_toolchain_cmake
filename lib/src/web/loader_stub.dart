// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'wasm_module.dart';

/// Loads an Emscripten module from [scriptUrl].
///
/// This stub is used on non-web platforms; it always throws
/// [UnsupportedError]. On the web it is replaced by the `dart:js_interop`
/// implementation.
///
/// [wasmBinary] is optional. When provided it is passed to the Emscripten
/// factory as `wasmBinary`, which avoids fetching the `.wasm` file separately
/// (handy when the asset URL is content-hashed). When omitted, Emscripten
/// resolves the `.wasm` file next to the JavaScript file.
///
/// [factoryName] must match the `-sEXPORT_NAME=<factoryName>` Emscripten
/// setting (`Module` by default).
Future<EmscriptenModule> loadEmscriptenModule({
  required Uri scriptUrl,
  List<int>? wasmBinary,
  String factoryName = 'Module',
  Map<String, Object?> moduleOptions = const {},
}) async {
  throw UnsupportedError(
    'Emscripten modules can only be loaded on the web. '
    'Import package:native_toolchain_cmake/web.dart from web code.',
  );
}
