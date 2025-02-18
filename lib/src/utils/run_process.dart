// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

/// Runs a [Process].
///
/// If [logger] is provided, stream stdout and stderr to it.
///
/// If [captureOutput], captures stdout and stderr.
Future<RunProcessResult> runProcess({
  required Uri executable,
  required Logger? logger,
  List<String> arguments = const [],
  Uri? workingDirectory,
  Map<String, String>? environment,
  bool captureOutput = true,
  int expectedExitCode = 0,
  bool throwOnUnexpectedExitCode = false,
}) async {
  final printWorkingDir = workingDirectory != null && workingDirectory != Directory.current.uri;
  final commandString = [
    if (printWorkingDir) '(cd ${workingDirectory.toFilePath()};',
    ...?environment?.entries.map((entry) => '${entry.key}=${entry.value}'),
    executable.toFilePath(),
    ...arguments.map((a) => a.contains(' ') ? "'$a'" : a),
    if (printWorkingDir) ')',
  ].join(' ');
  logger?.info('Running `$commandString`.');

  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final process = await Process.start(
    executable.toFilePath(),
    arguments,
    workingDirectory: workingDirectory?.toFilePath(),
    environment: environment,
    runInShell: Platform.isWindows,
  );

  final stdoutSub = process.stdout.listen(
    (List<int> data) {
      try {
        final decodedData = systemEncoding.decode(data);
        logger?.fine(decodedData);
        if (captureOutput) {
          stdoutBuffer.write(decodedData);
        }
      } catch (e) {
        logger?.warning('Failed to decode stdout: $e');
        stdoutBuffer.write('Failed to decode stdout: $e');
      }
    },
  );
  final stderrSub = process.stderr.listen(
    (List<int> data) {
      try {
        final decodedData = systemEncoding.decode(data);
        logger?.severe(decodedData);
        if (captureOutput) {
          stderrBuffer.write(decodedData);
        }
      } catch (e) {
        logger?.severe('Failed to decode stderr: $e');
        stderrBuffer.write('Failed to decode stderr: $e');
      }
    },
  );

  final (exitCode, _, _) =
      await (process.exitCode, stdoutSub.asFuture<void>(), stderrSub.asFuture<void>()).wait;

  await stdoutSub.cancel();
  await stderrSub.cancel();
  final result = RunProcessResult(
    pid: process.pid,
    command: commandString,
    exitCode: exitCode,
    stdout: stdoutBuffer.toString(),
    stderr: stderrBuffer.toString(),
  );
  if (throwOnUnexpectedExitCode && expectedExitCode != exitCode) {
    throw ProcessException(
      executable.toFilePath(),
      arguments,
      "Full command string: '$commandString'.\n"
      "Exit code: '$exitCode'.\n"
      'For the output of the process check the logger output.',
    );
  }
  return result;
}

/// Drop in replacement of [ProcessResult].
class RunProcessResult {
  final int pid;

  final String command;

  final int exitCode;

  final String stderr;

  final String stdout;

  RunProcessResult({
    required this.pid,
    required this.command,
    required this.exitCode,
    required this.stderr,
    required this.stdout,
  });

  @override
  String toString() => '''command: $command
exitCode: $exitCode
stdout: $stdout
stderr: $stderr''';
}
