// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_cmake/src/tool/tool_instance.dart';
import 'package:pub_semver/pub_semver.dart';

import '../builder/user_config.dart';
import '../tool/tool.dart';
import '../tool/tool_resolver.dart';

final ninja = Tool(name: 'Ninja', defaultResolver: _NinjaResolver());

@visibleForTesting
CliVersionResolver? unitTestNinjaAndroidResolver;
@visibleForTesting
CliVersionResolver? unitTestNinjaSystemResolver;

class _NinjaResolver implements ToolResolver {
  final executableName = OS.current.executableFileName('ninja');

  CliVersionResolver _getAndroidResolver({UserConfig? userConfig}) {
    return unitTestNinjaAndroidResolver ?? CliVersionResolver(
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
  }

  CliVersionResolver _getSystemResolver() {
    return unitTestNinjaSystemResolver ?? CliVersionResolver(
      wrappedResolver: PathToolResolver(toolName: 'Ninja', executableName: 'ninja'),
    );
  }

  @override
  Future<List<ToolInstance>> resolve({
    required Logger? logger,
    UserConfig? userConfig,
    Map<String, String>? environment,
  }) async {
    final androidResolver = _getAndroidResolver(userConfig: userConfig);
    final androidNinjaInstances = await androidResolver.resolve(logger: logger, environment: environment);
    logger?.info('Found Android Ninja: ${androidNinjaInstances.map((e) => e.toString()).join(', ')}');

    final systemResolver = _getSystemResolver();
    final systemNinjaInstances = await systemResolver.resolve(logger: logger, environment: environment);
    logger?.info('Found System Ninja: ${systemNinjaInstances.map((e) => e.toString()).join(', ')}');

    final combinedNinjaInstances = <ToolInstance>[];
    if (userConfig?.preferAndroidNinja ?? false) {
      androidNinjaInstances.sort(
        (a, b) => switch ((a.version, b.version)) {
          (null, null) => 0,
          (null, _) => 1,
          (_, null) => -1,
          (_, _) => -a.version!.compareTo(b.version!),
        },
      );
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
