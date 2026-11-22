//  ignore_for_file: dead_code
import 'dart:io';

import 'package:add/src/hook_helpers/hook_helpers.dart';
import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final sourceDir = Directory(await getPackagePath('add')).uri.resolve('src');
    const exampleGit = false;
    if (input.config.buildCodeAssets) {
      if (!exampleGit) {
        await runBuild(input, output, sourceDir);
      } else {
        await runBuildGit(input, output, sourceDir);
      }
    } else if (input.config.buildDataAssets) {
      await runWasmBuild(input, output, sourceDir);
    }
  });
}
