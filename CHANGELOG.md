# native_toolchain_cmake

## 0.0.6

- add `useVcvars` to `CMakeBuilder`
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
