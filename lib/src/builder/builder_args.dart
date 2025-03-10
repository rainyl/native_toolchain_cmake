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
