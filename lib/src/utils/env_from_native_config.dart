import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;

/// Set extra config from native_config.json
Future<Map<String, dynamic>> setExtraConfigFromNativeConfig({
  required BuildInput input,
  required String extraBuildConfigFile,
}) async {
  final hookInputUserDefines = input.json['user_defines'] as Map<String, dynamic>?;
  if (hookInputUserDefines == null) return {};

  final workspacePubspec = hookInputUserDefines['workspace_pubspec'] as Map<String, dynamic>?;
  if (workspacePubspec == null) return {};

  final basePath = workspacePubspec['base_path'] as String?;
  if (basePath == null) return {};

  final projectDir = path.dirname(basePath);
  final nativeConfigPath = path.join(projectDir, extraBuildConfigFile);
  final configFile = File(nativeConfigPath);
  if (!configFile.existsSync()) return {};

  return jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
}
