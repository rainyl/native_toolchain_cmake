import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

const name = 'add';

Future<void> runBuild(BuildInput input, BuildOutputBuilder output, Uri sourceDir) async {
  final builder = CMakeBuilder.create(
    name: name,
    sourceDir: sourceDir,
    buildMode: BuildMode.release,
    defines: {
      'CMAKE_INSTALL_PREFIX': input.outputDirectory.resolve('install').toFilePath(),
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
