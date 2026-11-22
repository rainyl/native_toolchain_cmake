# native_toolchain_cmake

A library to invoke CMake for Dart Native Assets.

## Status: Experimental

This library is experimental and may change without warning, use with caution!

## Example

Refer to [example](https://github.com/rainyl/native_toolchain_cmake/tree/main/example)

## Configuration

You can configure some options in your `pubspec.yaml`

```yaml
hooks:
  user_defines:
    <YOUR_PACKAGE_NAME_THAT_USES_NATIVE_TOOLCHAIN_CMAKE>: # e.g., dartcv4
      env_file: null # e.g., ".env"
      cmake_version: null # e.g., "3.22.1", if not specified, use the latest
      ninja_version: null # e.g., "1.10.2", if not specified, use the latest
      prefer_android_cmake: null # true or false, defaults to true for android
      prefer_android_ninja: null # true or false, defaults to true for android
      android:
        android_home: null # e.g., "C:\\Android\\Sdk" # can be set in .env file
        ndk_version: null # e.g., "28.2.13676358"
        cmake_version: null # e.g., "3.22.1", if not specified, fallback to global cmake_version
        # NOTE: Ninja is the default and only generator for Android
        ninja_version: null # e.g., "1.10.2", if not specified, fallback to global ninja_version
      ios:
        cmake_version: null # e.g., "3.22.1"
        # NOTE: you need to use Generator.ninja if you want to use Ninja for platforms except Android
        ninja_version: null # e.g., "1.10.2"
      windows:
        cmake_version: null # e.g., "3.22.1"
        ninja_version: null # e.g., "1.10.2"
      linux:
        cmake_version: null # e.g., "3.22.1"
        ninja_version: null # e.g., "1.10.2"
      web:
        emsdk_path: null # e.g., "/opt/emsdk" or "C:\emsdk"
        emscripten_root: null # e.g., "/opt/emsdk/upstream/emscripten"
        emscripten_toolchain_file: null # explicit Emscripten.cmake
        emscripten_version: null # e.g., "7.0.0" (>= 6.0.0)
      macos:
        cmake_version: null # e.g., "3.22.1"
        ninja_version: null # e.g., "1.10.2"
```

## NDK Discovery

When targeting Android, the NDK root directory is resolved in the following
order (aligned with the Flutter tool's
[AndroidSdk.locateAndroidSdk](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/android/android_sdk.dart)):

### SDK Root

1. `user_defines.android.android_home` (if set in `pubspec.yaml`)
2. `ANDROID_HOME` environment variable
3. Platform-default install location:
   - Linux:   `$HOME/Android/Sdk`
   - macOS:   `$HOME/Library/Android/sdk`
   - Windows: `%USERPROFILE%\AppData\Local\Android\Sdk`
4. `<dir>/sdk` fallback (for each hit above: if the directory itself is not a
   valid SDK but `<dir>/sdk` is, that subdirectory is used).
5. `aapt` on PATH → `parent.parent.parent` if it looks like an SDK root.
6. `adb` on PATH → `parent.parent` if it looks like an SDK root.

A directory qualifies as an SDK root if it contains a `platform-tools/` or
`licenses/` subdirectory.

### NDK Root

For each SDK root found above:

1. `ANDROID_NDK_HOME` (exact NDK root — highest priority)
2. `ANDROID_NDK_PATH` (fallback when `ANDROID_NDK_HOME` is unset)
3. `ANDROID_NDK_ROOT` (additional fallback)
4. `<sdk>/ndk/<version>/` directories sorted by `Version.parse` in descending
   order (latest first; entries that cannot be parsed as a [Version] are
   skipped).
5. Linux-only legacy `<sdk>/ndk-bundle/` (single-NDK layout).
6. `ndk-build` on PATH → parent directory (lowest priority).

If `user_defines.android.ndk_version` is specified, only NDK roots whose
basename parses to the requested version are kept; candidates without a
parseable basename (e.g. `ANDROID_NDK_HOME` pointing at a custom-named
directory, or `ndk-bundle`) are skipped.

## WebAssembly (web) builds

`CMakeWasmBuilder` builds CMake projects with [Emscripten](https://emscripten.org)
and exposes the generated `.js`/`.wasm` files to Dart and Flutter web.

### Requirements

- Emscripten SDK 6.0+ (`emsdk`), required for the `.exe` tool launchers and
  toolchain file layout. `emcc` is discovered in this order:
  1. `user_defines.web.emscripten_root`
  2. `user_defines.web.emsdk_path` (`upstream/emscripten`)
  3. `PATH`
  4. `EMSDK` (only available outside filtered hooks)
  5. common emsdk locations
  6. system installations / Homebrew.

  Build hooks run with a filtered environment and do not see `EMSDK`, so use
  `PATH` or `user_defines` there.
- Ninja and Node (`node` is used by CMake's Emscripten toolchain).
- CMake targets must be executables (`add_executable(add ...)`) producing
  `add.js` (and `add.wasm`), e.g. with `-sMODULARIZE=1` and
  `-sEXPORTED_FUNCTIONS`.

### Flutter / Dart data assets (experimental)

With Flutter tooling that supports data assets (currently the `master` channel
plus `flutter config --enable-dart-data-assets`), a build hook can emit the
artifacts as `DataAsset`s:

```dart
import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.config.buildCodeAssets) {
      // Native target: use CMakeBuilder.
      return;
    }
    if (input.config.buildDataAssets) {
      await CMakeWasmBuilder.create(
        name: 'add',
        sourceDir: Uri.directory('src/'),
        // singleFile: true, // embed the wasm in the JavaScript
      ).run(input: input, output: output);
    }
  });
}
```

This emits `wasm/add.js` and `wasm/add.wasm` (or only `wasm/add.js` with
`singleFile: true`). Flutter bundles them as
`assets/packages/<package>/wasm/...`.

### Flutter stable / pure Dart web / manual hosting

Use `runStandalone` and expose the files as regular Flutter assets (or serve
them yourself):

```dart
final files = await CMakeWasmBuilder.create(
  name: 'add',
  sourceDir: Uri.directory('src/'),
).runStandalone(outputDirectory: Uri.directory('build/wasm/'));
```

See `example/add/tool/build_wasm.dart` and `example/flutter/lib/web_bootstrap_web.dart`.

### Runtime loading

```dart
import 'package:native_toolchain_cmake/web.dart';

final module = await loadEmscriptenModule(
  scriptUrl: scriptUrl,
  wasmBinary: wasmBytes, // optional; avoids a separate .wasm fetch
  factoryName: 'addModule',
);
final result = module.callNum('math_add', args: [1, 2]);
```

`loadEmscriptenModule` works with both `flutter build web` (dart2js) and
`flutter build web --wasm` (dart2wasm). It only uses `package:web` and
`dart:js_interop`.

The build hook also records the resolved `emcc`, its version and the
`Emscripten.cmake` path in hook metadata, and adds both files to the hook
dependencies so an emsdk upgrade invalidates the cached build.

### Emscripten user_defines

```yaml
hooks:
  user_defines:
    <PACKAGE>:
      web:
        emsdk_path: null # e.g. "/opt/emsdk" or "C:\emsdk"
        emscripten_root: null # e.g. "/opt/emsdk/upstream/emscripten"
        emscripten_toolchain_file: null # explicit Emscripten.cmake
        emscripten_version: null # e.g. "7.0.0" (>= 6.0.0)
```


## Tree-shaking with a link hook

Linker dead-code elimination needs to know which native functions the compiled
Dart code calls. Only the **link hook** gets that information
(`input.recordedUses`), so the restricted link cannot happen in the build hook:
on a clean build there is nothing recorded yet, and a keep-list left over from
an earlier build strips symbols the new code needs.

`CMakeBuilder.runLink()` does that link hook work; the CMake project only has to
opt in:

```cmake
# CMakeLists.txt - after the shared library target is fully configured
include(${DNTCM_CMAKE_DIR}/treeshake.cmake)   # passed by CMakeBuilder
add_library(mylib SHARED src/lib.c)
target_link_libraries(mylib PRIVATE ...)
install(TARGETS mylib DESTINATION lib)
dntcm_add_treeshake_target(NAME mylib TARGET mylib)
```

```dart
// hook/build.dart - unchanged; on AOT builds the library and the build info of
// this build are handed to the link hook (routing: ToLinkHook).
await CMakeBuilder.create(name: 'mylib', sourceDir: ...).run(input: input, output: output);

// hook/link.dart
await link(args, (input, output) async {
  final symbols = symbolsFromRecordedUses(input); // empty without record-use
  if (symbols.isEmpty) {
    // No recorded usages (every SDK before the record-use experiment): ship the
    // library the build hook produced instead.
    // ...
    return;
  }
  await CMakeBuilder.forLink(name: 'mylib').runLink(
    input: input,
    output: output,
    assetName: 'mylib.dart',
    symbolsToKeep: symbols,
  );
});
```

`runLink()` writes the keep-list to `<build dir>/dntcm_keep_symbols_<lib>.txt`,
builds `mylib_treeshake` (`cmake --build ... --target mylib_treeshake`, no
reconfigure), copies the staged library from `<build dir>/dntcm_treeshake/` into
the link hook's output directory and registers it as the code asset. Every file
is per library and per build directory (`dntcm_build_info_<lib>.json`,
`dntcm_keep_symbols_<lib>.txt`, `dntcm_treeshake/<lib>`), so several libraries -
and several packages - never share one.

`DNTCM` is the prefix of everything this package puts into a CMake project:
**D**art **N**ative **T**oolchain **CM**ake. It returns
`false` (after logging why) when the build info, the keep-list or the staged
library is missing, and throws when the build fails, so a link hook can fall
back to the build hook's library. Symbols used through `@Native.addressOf`
(e.g. `NativeFinalizer` callbacks) are not recorded by the compiler - add them
to the keep-list yourself.

## Acknowledgements

- [native_toolchain_c](https://pub.dev/packages/native_toolchain_c)

## License

Apache-2.0 License
