// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_cmake/src/builder/run_builder.dart';
import 'package:test/test.dart';

void main() {
  final expectedToolchains = {
    Architecture.ia32: 'i686-linux-gnu.toolchain.cmake',
    Architecture.x64: 'x86_64-linux-gnu.toolchain.cmake',
    Architecture.arm64: 'aarch64-linux-gnu.toolchain.cmake',
    Architecture.riscv64: 'riscv64-linux-gnu.toolchain.cmake',
  };

  final crossCompilers = {
    Architecture.ia32: 'i686-linux-gnu-gcc',
    Architecture.x64: 'x86_64-linux-gnu-gcc',
    Architecture.arm64: 'aarch64-linux-gnu-gcc',
    Architecture.riscv64: 'riscv64-linux-gnu-gcc',
  };

  group('Linux toolchain selection', () {
    for (final MapEntry(key: architecture, value: fileName) in expectedToolchains.entries) {
      test('$architecture uses $fileName', () async {
        final builder = RunCMakeBuilder(
          sourceDir: Directory.current.absolute.uri,
          outDir: Directory.current.absolute.uri,
          targetOS: OS.linux,
          targetArchitecture: architecture,
        );

        final toolchain = await builder.linuxToolchainCmake();

        expect(toolchain.pathSegments.last, fileName);
        expect(File.fromUri(toolchain).existsSync(), isTrue);
      });

      test('$fileName selects the cross compiler for a foreign host', () async {
        final toolchainUri = Uri.directory(
          Directory.current.absolute.uri.toFilePath(),
        ).resolve('cmake/$fileName');
        final contents = await File.fromUri(toolchainUri).readAsString();

        // The cross compiler must be selected explicitly when the host does
        // not already target the requested architecture.
        expect(contents, contains('CMAKE_C_COMPILER "${crossCompilers[architecture]}"'));
        expect(contents, contains('CMAKE_HOST_SYSTEM_PROCESSOR'));
      });
    }

    test('unsupported architectures throw', () async {
      final builder = RunCMakeBuilder(
        sourceDir: Directory.current.absolute.uri,
        outDir: Directory.current.absolute.uri,
        targetOS: OS.linux,
        targetArchitecture: Architecture.arm,
      );

      expect(builder.linuxToolchainCmake(), throwsUnimplementedError);
    });
  });
}
