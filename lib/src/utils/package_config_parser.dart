// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

Future<String> getPackagePath(String packageName) async {
  final packageConfig = await _parsePackageConfig();
  for (final package in packageConfig.packages) {
    if (package case Package(name: final name, rootUri: final rootUri) when name == packageName) {
      return rootUri.toFilePath();
    }
  }
  throw Exception('Package "$packageName" not found');
}

class PackageConfig {
  final List<Package> packages;
  PackageConfig(this.packages);
}

class Package {
  final String name;
  final Uri rootUri;
  final Uri packageUri;
  Package(this.name, this.rootUri, this.packageUri);
}

Future<PackageConfig> _parsePackageConfig() async {
  final packageConfigUri =
      await Isolate.packageConfig ??
      (Platform.packageConfig != null
          ? Uri.parse(Platform.packageConfig!)
          : File('.dart_tool/package_config.json').absolute.uri);
  final file = File.fromUri(packageConfigUri);
  final projectDir = file.parent;
  final content = await file.readAsString();
  final json = jsonDecode(content);
  final packages = <Package>[];

  if (json case {'packages': final List packagesList}) {
    for (final entry in packagesList) {
      if (entry case {'name': final String name, 'rootUri': final String rootUriStr}) {
        final packageUriStr = switch (entry) {
          {'packageUri': final String uri} => uri,
          _ => 'lib/',
        };
        final packageUri = Uri.parse(packageUriStr);
        final rootUri = Uri.parse(rootUriStr);
        final resolvedRoot = rootUri.isAbsolute ? rootUri : projectDir.uri.resolveUri(rootUri);
        packages.add(Package(name, resolvedRoot, packageUri));
      }
    }
  }

  return PackageConfig(packages);
}
