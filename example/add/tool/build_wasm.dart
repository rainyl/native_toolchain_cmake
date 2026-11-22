// Standalone WebAssembly build for the `add` example (Flutter stable / pure
// Dart web / manual hosting).
//
// Usage:
//   dart run tool/build_wasm.dart
//   dart run tool/build_wasm.dart --single-file
//
// The generated add.js/add.wasm are written to build/wasm/.
import 'dart:io';

import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

Future<void> main(List<String> args) async {
  final root = Directory.current.uri;
  final builder = CMakeWasmBuilder.create(
    name: 'add',
    sourceDir: root.resolve('src/'),
    singleFile: args.contains('--single-file'),
    // Configure an emsdk checkout if emcc is not on PATH:
    // emscriptenArgs: const EmscriptenBuilderArgs(emsdkPath: '/opt/emsdk'),
  );

  final files = await builder.runStandalone(outputDirectory: root.resolve('build/wasm/'));

  for (final file in files) {
    stdout.writeln(file.toFilePath());
  }
}
