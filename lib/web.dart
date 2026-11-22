// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

/// Web / WebAssembly runtime helpers.
///
/// On non-web platforms the loader throws [UnsupportedError].
library;

export 'src/web/loader_stub.dart' if (dart.library.js_interop) 'src/web/loader_web.dart';
export 'src/web/wasm_module.dart';
