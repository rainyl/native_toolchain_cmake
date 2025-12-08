// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/src/tool/tool_instance.dart';
import 'package:pub_semver/pub_semver.dart';

import '../builder/user_config.dart';
import '../tool/tool.dart';
import '../tool/tool_resolver.dart';

final ninja = Tool(name: 'Ninja', defaultResolver: _NinjaResolver());

class _NinjaResolver implements ToolResolver {
  final executableName = OS.current.executableFileName('ninja');

  @override
  Future<List<ToolInstance>> resolve({required Logger? logger, UserConfig? userConfig}) async {
    final androidResolver = CliVersionResolver(
      wrappedResolver: ToolResolvers([
        if (userConfig?.preferAndroidNinja ?? false)
          InstallLocationResolver(
            toolName: 'Ninja',
            paths: [
              if (userConfig?.androidHome != null) '${userConfig?.androidHome}/cmake/*/bin/$executableName',
              if (Platform.isLinux) r'$HOME/Android/Sdk/cmake/*/bin/' + executableName,
              if (Platform.isMacOS) r'$HOME/Library/Android/sdk/cmake/*/bin/' + executableName,
              if (Platform.isWindows) r'$HOME/AppData/Local/Android/Sdk/cmake/*/bin/' + executableName,
            ],
          ),
      ]),
    );
    final androidNinjaInstances = await androidResolver.resolve(logger: logger);
    logger?.info('Found Android Ninja: ${androidNinjaInstances.map((e) => e.toString()).join(', ')}');

    final systemResolver = CliVersionResolver(
      wrappedResolver: PathToolResolver(toolName: 'Ninja', executableName: 'ninja'),
    );
    final systemNinjaInstances = await systemResolver.resolve(logger: logger);
    logger?.info('Found System Ninja: ${systemNinjaInstances.map((e) => e.toString()).join(', ')}');

    // sort latest version first
    androidNinjaInstances.sort((a, b) => a.version! > b.version! ? -1 : 1);
    final combinedNinjaInstances = <ToolInstance>[];
    if ((userConfig?.preferAndroidNinja ?? false) && androidNinjaInstances.isNotEmpty) {
      combinedNinjaInstances.addAll(androidNinjaInstances);
    }
    combinedNinjaInstances.addAll(systemNinjaInstances);

    if (userConfig?.ninjaVersion != null) {
      final ninjaVer = Version.parse(userConfig!.ninjaVersion!);
      combinedNinjaInstances.removeWhere((ninjaInstance) => ninjaInstance.version != ninjaVer);
      if (combinedNinjaInstances.isEmpty) {
        logger?.severe('Failed to find ninja version: ${userConfig.ninjaVersion}');
        throw Exception('Failed to find ninja version: ${userConfig.ninjaVersion}');
      }
    }

    return combinedNinjaInstances;
  }
}
