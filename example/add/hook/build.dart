import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/cmake.dart';
import 'package:native_toolchain_cmake/src/utils/run_process.dart';

Logger createCapturingLogger(List<String> capturedMessages) => Logger.detached('')
  ..level = Level.ALL
  ..onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    capturedMessages.add(record.message);
  });

void main(List<String> args) async {
  await build(args, (input, output) async {
    final sourceDir = Directory(await getPackagePath('add')).uri.resolve('src');
    final dstDir = Directory(await getPackagePath('add')).uri.resolve('build');
    assert(Directory(sourceDir.toFilePath()).existsSync());
    if (!Directory(dstDir.toFilePath()).existsSync()) {
      Directory(dstDir.toFilePath()).createSync(recursive: true);
    }
    // await runBuild(input, output, sourceDir.uri.resolve('src'));
    final messages = <String>[];
    final logger = createCapturingLogger(messages);
    final cm = (await cmake.defaultResolver?.resolve(logger: logger))?.first;
    assert(cm != null);
    // final result = await runProcess(
    //   executable: cm!.uri,
    //   arguments: [
    //     "-S",
    //     sourceDir.toFilePath(),
    //     "-B",
    //     dstDir.toFilePath(),
    //     "-DCMAKE_INSTALL_PREFIX=install",
    //     "-DCMAKE_BUILD_TYPE=Debug",
    //   ],
    //   logger: logger,
    //   captureOutput: true,
    //   throwOnUnexpectedExitCode: false,
    // );
    // assert(result.exitCode == 0);

    // NOTE: stucks
    // Process.runSync(
    //   cm!.uri.toFilePath(),
    //   [
    //     "-S",
    //     sourceDir.toFilePath(),
    //     "-B",
    //     dstDir.toFilePath(),
    //     "-DCMAKE_INSTALL_PREFIX=install",
    //   ],
    // );

    // NOTE: Also stucks
    final result = await runProcess(
      executable: cm!.uri,
      arguments: [
        "-S",
        sourceDir.toFilePath(),
        "-B",
        dstDir.toFilePath(),
        "-DCMAKE_INSTALL_PREFIX=install",
      ],
      logger: logger,
      captureOutput: true,
      throwOnUnexpectedExitCode: false,
    );
    assert(result.exitCode == 0);
  });
}
