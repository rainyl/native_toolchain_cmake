// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'package:native_assets_cli/code_assets.dart';

import '../tool/tool.dart';
import '../tool/tool_resolver.dart';

/// CMake for [Architecture.current].
final cmake = Tool(
  name: 'CMake',
  defaultResolver: CliVersionResolver(
    wrappedResolver: PathToolResolver(
      toolName: 'CMake',
      executableName: 'cmake',
    ),
  ),
);
