sealed class BuilderArgs {
  const BuilderArgs();
}

class AndroidBuilderArgs extends BuilderArgs {
  /// Android API level.
  ///
  /// default: null, will be inferred from BuildInput.config.code.android.targetNdkApi
  final int? androidAPI;

  /// Android ABI.
  ///
  /// default: null, will be inferred from BuildInput.config.code.targetArchitecture
  final String? androidABI;

  /// Android STL.
  ///
  /// default: c++_static
  final String androidSTL;

  /// Android ARM NEON.
  ///
  /// default: true
  final bool androidArmNeon;

  const AndroidBuilderArgs({
    this.androidAPI,
    this.androidABI,
    this.androidSTL = 'c++_static',
    this.androidArmNeon = true,
  });
}

// https://github.com/leetal/ios-cmake?tab=readme-ov-file#exposed-variables
class AppleBuilderArgs extends BuilderArgs {
  final bool enableBitcode;
  final bool enableArc;
  final bool enableVisibility;
  final bool enableStrictTryCompile;

  const AppleBuilderArgs({
    this.enableBitcode = false,
    this.enableArc = true,
    this.enableVisibility = true, // necessary to expose symbols
    this.enableStrictTryCompile = false,
  });
}

/// Emscripten / WebAssembly build configuration.
///
/// All paths are optional. When `null`, the builder falls back to the
/// package-level `user_defines.web` values, then to `EMSDK` / `PATH`
/// discovery. Note that build hooks run with a filtered environment, so
/// `EMSDK` is normally not visible; configure [emsdkPath] in `user_defines`
/// or ensure `emcc` is on `PATH`.
class EmscriptenBuilderArgs extends BuilderArgs {
  /// Root directory of an emsdk checkout, e.g. `/opt/emsdk` or
  /// `C:\emsdk`.
  ///
  /// The builder looks for
  /// `<emsdkPath>/upstream/emscripten/emcc[.exe]` and
  /// `<emsdkPath>/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake`.
  final String? emsdkPath;

  /// Root of an Emscripten installation, i.e. the directory that contains
  /// `emcc` and `cmake/Modules/Platform/Emscripten.cmake`.
  ///
  /// Use this for non-emsdk installations (system packages, Homebrew, ...).
  final String? emscriptenRoot;

  /// Explicit path to `Emscripten.cmake`.
  ///
  /// Takes precedence over [emscriptenRoot] and [emsdkPath].
  final String? toolchainFile;

  /// Optional Emscripten version to use, e.g. `7.0.0`.
  ///
  /// When set, only `emcc` binaries reporting this exact version are used.
  /// Emscripten 6.0.0 or newer is required.
  final String? version;

  /// Extra flags appended to `CMAKE_EXE_LINKER_FLAGS`.
  ///
  /// Use this for Emscripten `-s...` linker settings such as
  /// `-sEXPORTED_FUNCTIONS=['_foo']` or `-sMODULARIZE=1`.
  final List<String> linkerFlags;

  const EmscriptenBuilderArgs({
    this.emsdkPath,
    this.emscriptenRoot,
    this.toolchainFile,
    this.version,
    this.linkerFlags = const [],
  });
}
