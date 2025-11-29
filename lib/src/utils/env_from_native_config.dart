import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;

/// Get host specific build config
Future<Map<String, String>> getHostBuildConfig({
  required BuildInput input,
  required String hostBuildConfigFile,
}) async {
  final hookInputUserDefines = input.json['user_defines'] as Map<String, dynamic>?;
  if (hookInputUserDefines == null) return {};

  final workspacePubspec = hookInputUserDefines['workspace_pubspec'] as Map<String, dynamic>?;
  if (workspacePubspec == null) return {};

  final basePath = workspacePubspec['base_path'] as String?;
  if (basePath == null) return {};

  final projectDir = path.dirname(basePath);
  final nativeConfigPath = path.join(projectDir, hostBuildConfigFile);
  final configFile = File(nativeConfigPath);
  if (!configFile.existsSync()) return {};

  return _parseKeyValueFile(configFile);
}

Future<Map<String, String>> _parseKeyValueFile(File envFile) async {
  final lines = await envFile.readAsLines();
  final Map<String, String> result = {};

  for (final rawLine in lines) {
    final line = rawLine.trim();

    // Skip comments and blank lines
    if (line.isEmpty || line.startsWith('#')) continue;

    final eq = line.indexOf('=');
    if (eq == -1) continue;

    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();

    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }

    result[key] = value;
  }

  return result;
}
