// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'wasm_module.dart';

final _scriptLoads = <String, Future<void>>{};

/// Loads an Emscripten module from [scriptUrl] (the generated `.js` glue).
///
/// * [wasmBinary]: optional bytes passed as `module.wasmBinary`. Recommended
///   when the `.wasm` file is bundled as a Flutter asset, because it avoids
///   MIME type and content-hash URL issues.
/// * [factoryName]: `-sEXPORT_NAME=<name>` used at link time. Defaults to
///   `Module` (Emscripten's default with `-sMODULARIZE=1`).
/// * [moduleOptions]: extra options forwarded to the Emscripten factory.
Future<EmscriptenModule> loadEmscriptenModule({
  required Uri scriptUrl,
  List<int>? wasmBinary,
  String factoryName = 'Module',
  Map<String, Object?> moduleOptions = const {},
}) async {
  final factory = await _loadFactory(scriptUrl, factoryName);

  final options = JSObject();
  if (wasmBinary != null) {
    options.setProperty('wasmBinary'.toJS, Uint8List.fromList(wasmBinary).toJS);
  }
  for (final entry in moduleOptions.entries) {
    options.setProperty(entry.key.toJS, _toJS(entry.value));
  }

  final promise = factory.callAsFunction(null, options) as JSPromise<JSObject>?;
  if (promise == null) {
    throw StateError('Emscripten factory "$factoryName" did not return a promise.');
  }
  final module = await promise.toDart;
  return _WebEmscriptenModule(module);
}

Future<JSFunction> _loadFactory(Uri scriptUrl, String factoryName) async {
  if (!globalContext.has(factoryName)) {
    final key = scriptUrl.toString();
    var load = _scriptLoads[key];
    if (load == null) {
      load = _injectScript(scriptUrl);
      _scriptLoads[key] = load;
      try {
        await load;
      } catch (_) {
        // Allow a later retry instead of caching a permanently failed load.
        unawaited(_scriptLoads.remove(key));
        rethrow;
      }
    } else {
      await load;
    }
  }
  if (!globalContext.has(factoryName)) {
    throw StateError(
      'Emscripten factory "$factoryName" was not defined after loading '
      '$scriptUrl. Check -sEXPORT_NAME and that the script loaded successfully.',
    );
  }
  return globalContext.getProperty<JSFunction>(factoryName.toJS);
}

Future<void> _injectScript(Uri url) {
  final completer = Completer<void>();
  final script = HTMLScriptElement()
    ..src = url.toString()
    ..async = true;

  script.addEventListener(
    'load',
    ((Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS,
  );
  script.addEventListener(
    'error',
    ((Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Failed to load Emscripten script: $url'));
      }
    }).toJS,
  );

  document.head!.append(script);
  return completer.future;
}

class _WebEmscriptenModule implements EmscriptenModule {
  _WebEmscriptenModule(this._module);

  final JSObject _module;

  @override
  Object get raw => _module;

  @override
  num callNum(String function, {List<Object?> args = const [], List<String> argTypes = const []}) {
    final result = _ccall(function, 'number', args, argTypes);
    return (result! as JSNumber).toDartDouble;
  }

  @override
  String callString(String function, {List<Object?> args = const [], List<String> argTypes = const []}) {
    final result = _ccall(function, 'string', args, argTypes);
    return (result! as JSString).toDart;
  }

  @override
  void callVoid(String function, {List<Object?> args = const [], List<String> argTypes = const []}) {
    _ccall(function, 'number', args, argTypes);
  }

  JSAny? _ccall(String function, String returnType, List<Object?> args, List<String> argTypes) {
    if (argTypes.isNotEmpty && argTypes.length != args.length) {
      throw ArgumentError('argTypes ($argTypes) and args ($args) must have the same length.');
    }
    final types = argTypes.isEmpty ? List.filled(args.length, 'number') : argTypes;
    final ccall = _module.getProperty<JSFunction>('ccall'.toJS);
    return ccall.callAsFunction(
      null,
      function.toJS,
      returnType.toJS,
      [for (final type in types) type.toJS].toJS,
      [for (final arg in args) _toJS(arg)].toJS,
    );
  }
}

JSAny? _toJS(Object? value) {
  if (value == null) return null;
  if (value is JSAny) return value;
  if (value is num) return value.toJS;
  if (value is String) return value.toJS;
  if (value is bool) return value.toJS;
  return value.jsify();
}
