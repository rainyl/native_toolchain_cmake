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

## Acknowledgements

- [native_toolchain_c](https://pub.dev/packages/native_toolchain_c)

## License

Apache-2.0 License
