# native_toolchain_cmake

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
