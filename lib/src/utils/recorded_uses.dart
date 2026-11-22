// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'package:hooks/hooks.dart';

/// Maps the Dart function names that the compiler recorded to the native
/// symbols to keep, using [mapping] (a `*.record_use_mapping.g.dart` table)
/// where the two differ.
List<String> symbolsFromFunctionNames(Iterable<String> names, {Map<String, String> mapping = const {}}) => [
  for (final name in names) mapping[name] ?? name,
];

/// The native symbols of the `@ffi.Native` functions that the compiled Dart code
/// actually calls, for the keep-list of a tree-shaking link.
///
/// Only a link hook sees these usages (`LinkInput.recordedUses`); an SDK without
/// the `record-use` experiment (e.g. Dart 3.10) reports none, in which case the
/// result is empty and the caller should ship the unrestricted library.
///
/// The recorded keys are the Dart function names. FFIgen names the Dart
/// functions after the C symbols, so they can be used as-is; a package whose
/// names differ passes its `*.record_use_mapping.g.dart` table as [mapping].
///
/// Note that this cannot know about symbols used through `@Native.addressOf`
/// (e.g. `NativeFinalizer` callbacks): the compiler does not record those, so
/// add them to the keep-list yourself.
List<String> symbolsFromRecordedUses(LinkInput input, {Map<String, String> mapping = const {}}) {
  final recorded = input.recordedUses;
  if (recorded == null) return const [];
  return symbolsFromFunctionNames(recorded.calls.keys.map((call) => call.name), mapping: mapping);
}
