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

/// CMake for [Architecture.current].
final cmake = Tool(
  name: 'CMake',
  defaultResolver: CliVersionResolver(
    wrappedResolver: PathToolResolver(
      toolName: 'CMake',
      executableName: 'cmake',
    ),
  ),
);

/// CMake for the [OS.android].
final androidCmake = Tool(
  name: 'CMake',
  defaultResolver: _AndroidCmakeResolver(),
);

class _AndroidCmakeResolver implements ToolResolver {
  @override
  Future<List<ToolInstance>> resolve({required Logger? logger}) async {
    final installLocationResolver = PathVersionResolver(
      wrappedResolver: ToolResolvers([
        PathToolResolver(
          toolName: 'CMake',
          executableName: 'cmake',
        ),
        InstallLocationResolver(
          toolName: 'CMake',
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

    final cmakeInstances = await installLocationResolver.resolve(logger: logger);    

    final androidCmakeInstances = <ToolInstance>[];
    final systemCmakeInstances = <ToolInstance>[];
    for (final cmakeInstance in cmakeInstances) {
      final resolved = await tryResolveCmake(cmakeInstance, logger: logger);
      if (resolved != null) {
        androidCmakeInstances.add(resolved);
      } else {
        final systemCmakeResolved = await CliVersionResolver.lookupVersion(
          ToolInstance(
            tool: cmake,
            uri: cmakeInstance.uri,
          ),
          logger: logger,
        );
        systemCmakeInstances.add(systemCmakeResolved);
      }
    }

    final combinedCmakeInstances = <ToolInstance>[];
    // sort latest version first
    androidCmakeInstances.sort((a, b) => a.version! > b.version! ? -1 : 1);
    combinedCmakeInstances.addAll(androidCmakeInstances);
    combinedCmakeInstances.addAll(systemCmakeInstances);

    if (BuildExtraConfig.cmakeVersion != null) {
      final cmakeVer = Version.parse(BuildExtraConfig.cmakeVersion!);
      combinedCmakeInstances.removeWhere((cmakeInstance) => cmakeInstance.version != cmakeVer);
    }

    return combinedCmakeInstances;
  }

  Future<ToolInstance?> tryResolveCmake(
    ToolInstance androidCmakeInstance, {
    required Logger? logger,
  }) async {
    final prebuiltDir = Directory.fromUri(androidCmakeInstance.uri);
    final cmakeUri = prebuiltDir.uri.resolve(OS.current.executableFileName('cmake'));
    if (await File.fromUri(cmakeUri).exists()) {
      return CliVersionResolver.lookupVersion(
        ToolInstance(
          tool: androidCmake,
          uri: cmakeUri,
        ),
        logger: logger,
      );
    }
    return null;
  }
}
