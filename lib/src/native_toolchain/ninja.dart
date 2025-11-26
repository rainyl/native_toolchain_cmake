// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/src/builder/build_extra_config.dart';
import 'package:native_toolchain_cmake/src/tool/tool_instance.dart';
import 'package:pub_semver/pub_semver.dart';

import '../tool/tool.dart';
import '../tool/tool_resolver.dart';

/// Ninja for [Architecture.current].
final ninja = Tool(
  name: 'Ninja',
  defaultResolver: CliVersionResolver(
    wrappedResolver: PathToolResolver(
      toolName: 'Ninja',
      executableName: 'ninja',
    ),
  ),
);

/// Ninja for the [OS.android].
final androidNinja = Tool(
  name: 'Ninja',
  defaultResolver: _AndroidNinjaResolver(),
);

class _AndroidNinjaResolver implements ToolResolver {
  @override
  Future<List<ToolInstance>> resolve({required Logger? logger}) async {
    final installLocationResolver = PathVersionResolver(
      wrappedResolver: ToolResolvers([
        PathToolResolver(
          toolName: 'Ninja',
          executableName: 'ninja',
        ),
        InstallLocationResolver(
          toolName: 'Ninja',
          paths: [
            if (BuildExtraConfig.androidHome != null) ...[
              '${BuildExtraConfig.androidHome}/cmake/*/bin/',
            ],
            if (Platform.isLinux) ...[
              r'$HOME/Android/Sdk/cmake/*/bin/',
            ],
            if (Platform.isMacOS) ...[
              r'$HOME/Library/Android/sdk/cmake/*/bin/',
            ],
            if (Platform.isWindows) ...[
              r'$HOME/AppData/Local/Android/Sdk/cmake/*/bin/',
            ],
          ],
        ),
      ]),
    );

    final ninjaInstances = await installLocationResolver.resolve(logger: logger);    

    final androidNinjaInstances = <ToolInstance>[];
    final systemNinjaInstances = <ToolInstance>[];
    for (final ninjaInstance in ninjaInstances) {
      final resolved = await tryResolveNinja(ninjaInstance, logger: logger);
      if (resolved != null) {
        androidNinjaInstances.add(resolved);
      } else {
        final systemNinjaResolved = await CliVersionResolver.lookupVersion(
          ToolInstance(
            tool: ninja,
            uri: ninjaInstance.uri,
          ),
          logger: logger,
        );
        systemNinjaInstances.add(systemNinjaResolved);
      }
    }

    final combinedNinjaInstances = <ToolInstance>[];
    // sort latest version first
    androidNinjaInstances.sort((a, b) => a.version! > b.version! ? -1 : 1);
    combinedNinjaInstances.addAll(androidNinjaInstances);
    combinedNinjaInstances.addAll(systemNinjaInstances);

    if (BuildExtraConfig.ninjaVersion != null) {
      final ninjaVer = Version.parse(BuildExtraConfig.ninjaVersion!);
      combinedNinjaInstances.removeWhere((ninjaInstance) => ninjaInstance.version != ninjaVer);
      if (combinedNinjaInstances.isEmpty) {
        logger?.severe('Failed to find ninja version: ${BuildExtraConfig.ninjaVersion}');
        throw Exception('Failed to find ninja version: ${BuildExtraConfig.ninjaVersion}');
      }
    }

    return combinedNinjaInstances;
  }

  Future<ToolInstance?> tryResolveNinja(
    ToolInstance androidNinjaInstance, {
    required Logger? logger,
  }) async {
    final prebuiltDir = Directory.fromUri(androidNinjaInstance.uri);
    final ninjaUri = prebuiltDir.uri.resolve(OS.current.executableFileName('ninja'));
    if (await File.fromUri(ninjaUri).exists()) {
      return CliVersionResolver.lookupVersion(
        ToolInstance(
          tool: androidNinja,
          uri: ninjaUri,
        ),
        logger: logger,
      );
    }
    return null;
  }
}
