import 'dart:io';

import 'package:native_assets_cli/native_assets_cli.dart';

import 'package:example/src/hook_helpers/hook_helpers.dart';

final sourceDir = Directory('src');

void main(List<String> args) async {
  await build(args, (input, output) async {
    await runBuild(input, output, sourceDir.uri);
  });
}
