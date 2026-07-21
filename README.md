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

## Acknowledgements

- [native_toolchain_c](https://pub.dev/packages/native_toolchain_c)

## License

Apache-2.0 License
