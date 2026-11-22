// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

/// A loaded Emscripten module.
///
/// Instances are created by `loadEmscriptenModule` from
/// `package:native_toolchain_cmake/web.dart`.
abstract interface class EmscriptenModule {
  /// The underlying JavaScript module object.
  ///
  /// Use this with `dart:js_interop` if you need direct access to the exports.
  Object get raw;

  /// Calls an exported C function that returns a number.
  ///
  /// [argTypes] defaults to all `number` arguments. Use Emscripten `ccall`
  /// types such as `number`, `string`, `boolean`, or `array` for other
  /// arguments. Example:
  ///
  /// ```dart
  /// final result = module.callNum('add', args: [1, 2]);
  /// final ok = module.callNum(
  ///   'open',
  ///   args: [':memory:'],
  ///   argTypes: ['string'],
  /// );
  /// ```
  num callNum(String function, {List<Object?> args = const [], List<String> argTypes = const []});

  /// Calls an exported C function that returns a string.
  ///
  /// Strings are only supported if the function returns a `char*`.
  String callString(String function, {List<Object?> args = const [], List<String> argTypes = const []});

  /// Calls an exported C function and discards the return value.
  void callVoid(String function, {List<Object?> args = const [], List<String> argTypes = const []});
}
