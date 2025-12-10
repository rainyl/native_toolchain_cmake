import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

/// Get host specific build config
Future<Map<String, String>> getUserEnvConfig({required BuildInput input, required String envFile}) async {
  final hookInputUserDefines = input.json['user_defines'] as Map<String, dynamic>?;
  if (hookInputUserDefines == null) return {};

  final workspacePubspec = hookInputUserDefines['workspace_pubspec'] as Map<String, dynamic>?;
  if (workspacePubspec == null) return {};

  final basePath = workspacePubspec['base_path'] as String?;
  if (basePath == null) return {};

  // base_path may be a directory when testing.
  final projectDir = FileSystemEntity.isDirectorySync(basePath) ? basePath : p.dirname(basePath);
  final envConfigPath = p.join(projectDir, envFile);
  final configFile = File(envConfigPath);
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
