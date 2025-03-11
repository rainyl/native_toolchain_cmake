import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

const name = 'add';

Future<void> runBuild(
  BuildInput input,
  BuildOutputBuilder output,
  Uri sourceDir,
) async {
  final _logger = Logger('')
    ..level = Level.ALL
    // temp fwd to stderr until process logs pass to stdout
    ..onRecord.listen((record) => stderr.writeln(record));
  final builder = CMakeBuilder.create(
    name: name,
    sourceDir: sourceDir,
    defines: {
      'CMAKE_BUILD_TYPE': 'Release',
      'CMAKE_INSTALL_PREFIX': '${input.outputDirectory.toFilePath()}/install',
    },
    targets: [
      'install',
    ],
    buildLocal: true,
    logger: _logger,
  );

  await builder.run(input: input, output: output, logger: _logger);

  final outLibs = await addLibraries(
    input,
    output,
    Uri.file("${input.outputDirectory.toFilePath()}/install"),
    packageName: name,
    staticLibNames: [name],
    dynLibNames: [name],
    logger: _logger,
  );
}

Future<void> runBuildGit(
  BuildInput input,
  BuildOutputBuilder output,
  Uri sourceDir,
) async {
  final logger = Logger('')
    ..level = Level.ALL
    // temp fwd to stderr until process logs pass to stdout
    ..onRecord.listen((record) => stderr.writeln(record));
  // From git url
  final builder = CMakeBuilder.fromGit(
    gitUrl: "https://github.com/rainyl/native_toolchain_cmake.git",
    sourceDir: sourceDir,
    name: name,
    gitSubDir: "example/add/src",
    defines: {
      'CMAKE_BUILD_TYPE': 'Release',
      'CMAKE_INSTALL_PREFIX': '${input.outputDirectory.toFilePath()}/install',
    },
    targets: ['install'],
    buildLocal: true,
    logger: logger,
  );

  await builder.run(
    input: input,
    output: output,
    logger: logger,
  );

  final libPath = switch (input.config.code.targetOS) {
    OS.linux => "install/lib/libadd.so",
    OS.macOS => "install/lib/libadd.dylib",
    OS.windows => "install/lib/add.dll",
    OS.android => "install/lib/libadd.so",
    OS.iOS => "install/lib/libadd.dylib",
    _ => throw UnsupportedError("Unsupported OS")
  };
  output.assets.code.add(
    CodeAsset(
      package: name,
      name: '$name.dart',
      linkMode: DynamicLoadingBundled(),
      os: input.config.code.targetOS,
      file: input.outputDirectory.resolve(libPath),
      architecture: input.config.code.targetArchitecture,
    ),
  );
}
