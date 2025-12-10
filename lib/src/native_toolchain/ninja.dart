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
    if ((userConfig?.preferAndroidNinja ?? false) || userConfig?.targetOS == OS.android) {
      combinedNinjaInstances.addAll(androidNinjaInstances);
    }
    combinedNinjaInstances.addAll(systemNinjaInstances);
    for (final instance in combinedNinjaInstances) {
      if (instance.version == null) {
        logger?.warning('Can not determine version of: $instance');
      }
    }

    final specificNinjaVersion = userConfig?.ninjaVersion;
    if (specificNinjaVersion != null) {
      final ninjaVer = Version.parse(specificNinjaVersion);
      logger?.info('Filtering Ninja version: $ninjaVer');
      combinedNinjaInstances.removeWhere(
        (instance) =>
            instance.version == null ||
            instance.version!.major != ninjaVer.major ||
            instance.version!.minor != ninjaVer.minor ||
            instance.version!.patch != ninjaVer.patch,
      );
    }

    logger?.info('Found Ninja: ${combinedNinjaInstances.map((e) => e.toString()).join(', ')}');
    if (combinedNinjaInstances.isEmpty) {
      logger?.severe('Failed to find ninja with version=${specificNinjaVersion ?? 'latest'}');
      throw Exception('Failed to find ninja version: ${specificNinjaVersion ?? 'latest'}');
    }

    return combinedNinjaInstances;
  }
}
