// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

const name = 'example.dart';

Future<void> runBuild(BuildInput input, BuildOutputBuilder output, String sourceDir) async {
  final builder = CMakeBuilder.create(
    name: name,
    assetName: '$name.dart',
    sourceDir: sourceDir,
    defines: {
      'CMAKE_BUILD_TYPE': 'Release',
      'CMAKE_INSTALL_PREFIX': '${input.outputDirectory.toFilePath()}/install',
    },
    targets: ['install'],
  );
  await builder.run(
    input: input,
    output: output,
    logger: Logger('')
      ..level = Level.ALL
      ..onRecord.listen((record) => print(record.message)),
  );
  output.assets.code.add(CodeAsset(
    package: 'example',
    name: name,
    linkMode: DynamicLoadingBundled(),
    os: input.config.code.targetOS,
    file: Directory(input.outputDirectory.toFilePath()).uri.resolve("install/lib/add.dll"),
    architecture: input.config.code.targetArchitecture,
  ));
}
