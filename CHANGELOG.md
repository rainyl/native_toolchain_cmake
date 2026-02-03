# native_toolchain_cmake

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
