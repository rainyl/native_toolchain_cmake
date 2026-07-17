@OnPlatform({'mac-os': Timeout.factor(2), 'windows': Timeout.factor(10)})
library;

import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final targetOS = OS.current;

  test('CMakeBuilder.create runStandalone executable', () async {
    final tempUri = await tempDirForTest();
    const name = 'hello_world';
    final builder = CMakeBuilder.create(
      name: name,
      sourceDir: Directory('test/builder/testfiles/hello_world').uri,
      buildMode: BuildMode.release,
    );

    await builder.runStandalone(
      outputDirectory: tempUri,
      targetOS: targetOS,
      targetArchitecture: Architecture.current,
    );

    final executableUri = switch (targetOS) {
      OS.macOS => tempUri.resolve('$name.app/Contents/MacOS/${OS.current.executableFileName(name)}'),
      OS.windows => tempUri.resolve('Release/$name.exe'),
      _ => tempUri.resolve(OS.current.executableFileName(name)),
    };
    expect(await File.fromUri(executableUri).exists(), true);
    final result = await runProcess(executable: executableUri, logger: logger);
    expect(result.exitCode, 0);
    expect(result.stdout.trim(), endsWith('Hello world.'));
  });

  test('CMakeBuilder.create runStandalone library', () async {
    final tempUri = await tempDirForTest();
    const name = 'add';

    final builder = CMakeBuilder.create(
      name: name,
      sourceDir: Directory('test/builder/testfiles/add').uri,
      buildMode: BuildMode.release,
      defines: {'CMAKE_INSTALL_PREFIX': tempUri.resolve('install/').toFilePath()},
      targets: ['install'],
    );

    await builder.runStandalone(
      outputDirectory: tempUri,
      targetOS: targetOS,
      targetArchitecture: Architecture.current,
    );

    final dylibUri = tempUri.resolve('install/lib/${OS.current.dylibFileName(name)}');
    expect(await File.fromUri(dylibUri).exists(), true);
    final dylib = openDynamicLibraryForTest(dylibUri.toFilePath());
    final add = dylib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('add');
    expect(add(1, 2), 3);
  });
}
