# native_toolchain_cmake

## 0.4.0-beta.3

- fix: locate `Emscripten.cmake` for Homebrew installs, whose Emscripten tree and `emcc` wrapper live in `libexec/`

## 0.4.0-beta.2

- fix: tree-shaking on Apple platforms (iOS, macOS): the tree-shaken library is staged with `install(TARGETS ...)` and installed by `runLink`, because a POST_BUILD copy of `$<TARGET_FILE:...>` fails on the Xcode generator
- fix: require `code_assets` 2.x; with 1.x every hook invocation threw `FormatException: The OS "web" is not known`

## 0.4.0-beta.1

- new: `CMakeBuilder.runLink()` links the final library in a link hook (`hook/link.dart`) with only the native symbols the compiled Dart code uses, which is the only hook that knows them (`symbolsFromRecordedUses()`, or a keep-list of your own). The build hook records where it built (`CMakeBuildInfo`), so the link hook does not need to know how to build anything.
- new: `cmake/treeshake.cmake`: `dntcm_add_treeshake_target(NAME <lib> TARGET <shared lib>)` adds a `<lib>_treeshake` variant that exports only the keep-list symbols (Apple `-exported_symbols_list` + `-dead_strip`, ELF `--version-script` + `--gc-sections`, MSVC `/DEF:` + `/OPT:REF`) and stages it in `<build dir>/dntcm_treeshake/` for `runLink`. `CMakeBuilder` passes the module directory as `-DDNTCM_CMAKE_DIR`; `DNTCM` is the prefix of everything this package puts into a CMake project (Dart Native Toolchain CMake), and the files it writes (`dntcm_build_info_<lib>.json`, `dntcm_keep_symbols_<lib>.txt`, `dntcm_treeshake/<lib>`) are per library and per build directory.
- new: `RunCMakeBuilder.buildTarget()` builds targets of an already generated tree without re-running the generate step.
- new: `symbolsFromFunctionNames()` / `symbolsFromRecordedUses()` map recorded `@ffi.Native` usages to a keep-list.
- new: `dntcmCmakeDir()`, and `RunCMakeBuilder` is exported so `buildTarget()` is reachable from outside the package.
- change: the `CMakeBuildInfo.buildMode` of the record `CMakeBuilder.run()` writes is the `BuildMode` name (`release` / `debug`) instead of the display string (`Release`). The file-name helpers of that record are `@visibleForTesting`.
- fix: `getUserEnvConfig()` accepts any `HookInput`, not only a `BuildInput`.
- breaking: requires `hooks` 2.1+ (`LinkInput.recordedUses`)

## 0.4.0-beta.0

- breaking: requires `hooks` 2.x (needed for `data_assets`)
- breaking: Emscripten 6.0+ is required (older emsdk releases are rejected)
- new: `CMakeWasmBuilder` builds CMake projects with Emscripten and emits `.js`/`.wasm` as web data assets (`run`) or to a directory (`runStandalone`)
- new: `package:native_toolchain_cmake/web.dart` provides `loadEmscriptenModule` / `EmscriptenModule` for calling wasm from Dart and Flutter web
- new: `singleFile` option embeds the wasm in the JavaScript (`-sSINGLE_FILE=1`)
- new: `user_defines.web.{emsdk_path,emscripten_root,emscripten_toolchain_file,emscripten_version}`

## 0.3.3

- new: support cross-compiling to 32-bit x86 Linux (`Architecture.ia32`) via `cmake/i686-linux-gnu.toolchain.cmake`
- fix: select the Linux toolchain purely by target architecture; the toolchain files now choose the host compiler only when the host matches the target and otherwise use the matching `*-linux-gnu-gcc` cross compiler, so cross-compiling from e.g. arm64 to x64 no longer picks the native (arm64) `gcc`

## 0.3.2

- widen the `code_assets` constraint to `>=1.0.0 <3.0.0` to allow `code_assets` 2.x, which is compatible with both 1.x and 2.x

## 0.3.1

- fix: fall back to the default `PATHEXT` when resolving tools with `where` on Windows, fixes CMake/Ninja resolution in filtered environments such as build hooks, [#40](https://github.com/rainyl/native_toolchain_cmake/issues/40)

## 0.3.0

- fix: properly resolve user-defines for android_home on Windows, [#37](https://github.com/rainyl/native_toolchain_cmake/issues/37)
- feat: align android SDK and NDK resolver with Flutter's implementation, [#31](https://github.com/rainyl/native_toolchain_cmake/issues/31)
- Breaking change: the Android SDK and NDK resolving logic may be a breaking change

## 0.2.7

- new: add `CMakeBuilder.runStandalone` to allow running builder without `BuildInput input` and `BuildOutputBuilder output`

## 0.2.6

- bump hooks to 2.0

## 0.2.5

- fix: add encoding parameter (default is `systemEncoding`) to runProcess for consistent output decoding

## 0.2.4

- new: add `parallelJobs` and `parallelUseAllProcessors` to support parallel build or set njobs explicitly.

## 0.2.3

- new: support skipping generate if cached
- feat: check for prelrease VS version if no stable version is found
- fix: pass environment variables from vcvars.bat to resolvers to allow finding cmake not in PATH

## 0.2.2

- find all available visual studio versions

## 0.2.1

- support configuring cmake/ninja versions and android NDK version
- mock cmake/ninja when testing

## 0.2.0

- bump hooks and code_assets to 1.0.0

## 0.1.0

- migrate to `hooks` and `code_assets`
- fix: ambiguous ios/arm64 for iosSimulator/arm64
- bump hooks to 0.20.0

## 0.0.6-dev.1

- fix: ambiguous ios/arm64 for iosSimulator/arm64

## 0.0.6-dev.0

- migrate to `hooks` and `code_assets`

## 0.0.5

- fix: only add `-A` when using Visual Studio Generators
- new: add `useVcvars` to add environment variables from vcvarsXXX.bat
- bump native_assets_cli to 0.13.0

## 0.0.4

- fix: android should use Ninja for android builds
- fix: fixed a uri resolution issue for the local build folder
- fix: use the input's target OS instead of current.OS
- fix: null value in tool resolution
- new: add extension methods `BuildOutputBuilder.findCodeAssets`, `BuildOutputBuilder.addAllCodeAssets`
- breaking change: `BuildOutputBuilder.findAndAddCodeAssets` now returns `List<CodeAsset>`

## 0.0.3

- new: add `CMakeBuilder.fromGit` constructor to create a builder from a remote repository.
- new: add `buildLocal` optional parameter to build out of `.dart_tool`.
- new: add `AddFoundCodeAssets`, `BuildOutputBuilder.findAndAddCodeAssets` to find and add code assets.
- breaking change: move android and `ios.toolchain.cmake` related args of `CMakeBuilder` to separate `AndroidBuilderArgs` and `AppleBuilderArgs`.

## 0.0.2

- use `SystemEncoding` to decode the output of `Process`
- add `--log-level` for CMake

## 0.0.1

- initial release
