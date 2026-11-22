import 'package:add/add.dart' as add;
import 'package:flutter/services.dart';

/// Resolves the hook-generated data assets and loads the Emscripten module.
///
/// Requires Flutter with data asset support (currently the `master` channel
/// plus `flutter config --enable-dart-data-assets`).
Future<void> initAddForWeb() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

  const jsKey = 'packages/add/wasm/add.js';
  final jsVariants = manifest.getAssetVariants(jsKey);
  if (jsVariants == null || jsVariants.isEmpty) {
    throw StateError(
      'Missing web asset "$jsKey". Build with Flutter master and '
      '`flutter config --enable-dart-data-assets`, or use the standalone '
      '`dart run tool/build_wasm.dart` flow.',
    );
  }
  // The manifest key is content-hashed when web content hashing is enabled.
  final scriptUrl = Uri.base.resolve('assets/${jsVariants.first.key}');

  const wasmKey = 'packages/add/wasm/add.wasm';
  final wasmVariants = manifest.getAssetVariants(wasmKey);
  List<int>? wasmBytes;
  if (wasmVariants != null && wasmVariants.isNotEmpty) {
    final data = await rootBundle.load(wasmKey);
    wasmBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  await add.initAdd(scriptUrl: scriptUrl, wasmBinary: wasmBytes);
}
