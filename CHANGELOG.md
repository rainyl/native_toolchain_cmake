# native_toolchain_cmake

## 0.0.4

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
