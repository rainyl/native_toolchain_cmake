// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

class Generator {
  final String name;

  const Generator._(this.name);

  static const Generator ninja = Generator._('Ninja');

  static const Generator make = Generator._('Unix Makefiles');

  static const Generator xcode = Generator._('Xcode');

  static const Generator vs2019 = Generator._('Visual Studio 16 2019');

  static const Generator vs2022 = Generator._('Visual Studio 17 2022');

  static const Generator defaultGenerator = Generator._("default");
}
