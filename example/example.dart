//  ignore_for_file: dead_code
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final sourceDir = Directory(await getPackagePath('add')).uri.resolve('src');
    const exampleGit = false;
    if (!exampleGit) {
      await runBuild(input, output, sourceDir);
    } else {
      await runBuildGit(input, output, sourceDir);
    }
  });
}

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

  final buildjson = input.config.json;
  _logger.info('Build output: $buildjson');

  // automatically search and add libraries
  final outLibs = await output.findAndAddCodeAssets(
    input,
    names: {r'(lib)?add\.(dll|so|dylib)': 'add.dart'},
    outDir: input.outputDirectory.resolve('install'),
    logger: _logger,
    regExp: true,
  );

  // Do something else with outLibs uris
  _logger.info('Found libs: $outLibs');
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

  // manually add assets
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
