// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

Future<String> getPackagePath(String packageName) async {
  final packageConfig = await _parsePackageConfig();
  for (final package in packageConfig.packages) {
    if (package.name == packageName) {
      return package.rootUri.toFilePath();
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
  final file = File.fromUri(Uri.parse(Platform.packageConfig!));
  final projectDir = file.parent;
  final content = await file.readAsString();
  final json = jsonDecode(content) as Map<String, dynamic>;
  final packages = <Package>[];

  for (final entry in json['packages'] as List) {
    final name = entry['name'] as String;
    final rootUri = Uri.parse(entry['rootUri'] as String);
    final packageUri = Uri.parse(entry['packageUri'] as String? ?? 'lib/');

    final pkg = Package(name, rootUri.isAbsolute ? rootUri : projectDir.uri.resolveUri(rootUri), packageUri);

    packages.add(pkg);
  }

  return PackageConfig(packages);
}
