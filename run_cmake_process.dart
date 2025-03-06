import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/src/native_toolchain/cmake.dart';
import 'package:native_toolchain_cmake/src/utils/run_process.dart';

Logger createCapturingLogger(List<String> capturedMessages) => Logger.detached('')
  ..level = Level.ALL
  ..onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    capturedMessages.add(record.message);
  });

// works fine
void main(List<String> args) async {
  final messages = <String>[];
  final logger = createCapturingLogger(messages);
  final cm = (await cmake.defaultResolver?.resolve(logger: logger))?.first;
  final srcDir = Directory("example/add/src");
  final dstDir = Directory("example/add/build");
  assert(cm != null);
  final result = await runProcess(
    executable: cm!.uri,
    arguments: [
      "-S",
      srcDir.path,
      "-B",
      dstDir.path,
      "-DCMAKE_INSTALL_PREFIX=install",
    ],
    logger: logger,
    captureOutput: true,
    throwOnUnexpectedExitCode: false,
  );
  assert(result.exitCode == 0);
}
