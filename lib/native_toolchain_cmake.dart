// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

/// A library to invoke CMake for Dart Native Assets.
library;

export 'src/builder/build_info.dart';
export 'src/builder/build_mode.dart';
export 'src/builder/builder.dart' show CMakeBuilder;
export 'src/builder/builder_args.dart';
export 'src/builder/generator.dart';
export 'src/builder/link_builder.dart' show CMakeLinkBuilder;
export 'src/builder/log_level.dart';
export 'src/builder/run_builder.dart' show RunCMakeBuilder;
export 'src/builder/wasm_builder.dart';
export 'src/native_toolchain/emscripten.dart' show emcc, findEmscriptenToolchainFile, resolveEmscripten;
export 'src/utils/add_assets.dart';
export 'src/utils/env_from_bat.dart';
export 'src/utils/package_config_parser.dart';
export 'src/utils/recorded_uses.dart';
