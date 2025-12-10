// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../builder/user_config.dart';
import '../tool/tool.dart';
import '../tool/tool_instance.dart';
import '../tool/tool_resolver.dart';

/// CMake.
final cmake = Tool(name: 'CMake', defaultResolver: _CmakeResolver());

class _CmakeResolver implements ToolResolver {
  final executableName = OS.current.executableFileName('cmake');

  @override
  Future<List<ToolInstance>> resolve({required Logger? logger, UserConfig? userConfig}) async {
    // here, we always try to find android cmake first and filter out unsatisfied versions
    final androidResolver = CliVersionResolver(
      wrappedResolver: ToolResolvers([
        InstallLocationResolver(
          toolName: 'CMake',
          paths: [
            if (userConfig?.androidHome != null) '${userConfig?.androidHome}/cmake/*/bin/$executableName',
            if (Platform.isLinux) r'$HOME/Android/Sdk/cmake/*/bin/' + executableName,
            if (Platform.isMacOS) r'$HOME/Library/Android/sdk/cmake/*/bin/' + executableName,
            if (Platform.isWindows) r'$HOME/AppData/Local/Android/Sdk/cmake/*/bin/' + executableName,
          ],
        ),
      ]),
    );
    final androidCmakeInstances = await androidResolver.resolve(logger: logger);
    logger?.info('Found Android CMake: ${androidCmakeInstances.map((e) => e.toString()).join(', ')}');

    final systemResolver = CliVersionResolver(
      wrappedResolver: PathToolResolver(toolName: 'CMake', executableName: 'cmake'),
    );
    final systemCmakeInstances = await systemResolver.resolve(logger: logger);
    logger?.info('Found System CMake: ${systemCmakeInstances.map((e) => e.toString()).join(', ')}');

    // sort latest version first
    androidCmakeInstances.sort((a, b) => a.version! > b.version! ? -1 : 1);
    final combinedCmakeInstances = <ToolInstance>[];
    if ((userConfig?.preferAndroidCmake ?? false) || userConfig?.targetOS == OS.android) {
      combinedCmakeInstances.addAll(androidCmakeInstances);
    }
    combinedCmakeInstances.addAll(systemCmakeInstances);
    for (final instance in combinedCmakeInstances) {
      if (instance.version == null) {
        logger?.warning('Can not determine version of: $instance');
      }
    }

    final specificCmakeVersion = userConfig?.cmakeVersion;
    if (specificCmakeVersion != null) {
      final cmakeVer = Version.parse(specificCmakeVersion);
      logger?.info('Filtering CMake version: $cmakeVer');
      // cmake version of android are likely to be the format of `3.22.1-g37088a8-dirty`
      // so here we just check the major, minor and patch version
      combinedCmakeInstances.removeWhere(
        (instance) =>
            instance.version == null ||
            instance.version?.major != cmakeVer.major ||
            instance.version?.minor != cmakeVer.minor ||
            instance.version?.patch != cmakeVer.patch,
      );
    }

    logger?.info('Found CMake: ${combinedCmakeInstances.map((e) => e.toString()).join(', ')}');
    if (combinedCmakeInstances.isEmpty) {
      logger?.severe('Failed to find cmake with version=${specificCmakeVersion ?? 'latest'}');
      throw Exception('Failed to find cmake version: ${specificCmakeVersion ?? 'latest'}');
    }

    return combinedCmakeInstances;
  }
}
