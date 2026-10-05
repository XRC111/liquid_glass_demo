import 'dart:ui' as ui;

/// 着色器加载与生命周期管理。
///
/// 三份 GLSL 片元着色器在构建期由 Flutter 工具链编译为
/// Vulkan (SPIR-V) 与 OpenGL ES 两套目标，运行期通过
/// [ui.FragmentProgram.fromAsset] 加载：
///
/// ```dart
/// final program = await FragmentProgram.fromAsset('shaders/liquid_glass.frag');
/// final shader = program.fragmentShader();
/// shader.setFloat(0, size.width);
/// shader.setImageSampler(0, backgroundImage);
/// ```
class GlassShaderProgram {
  GlassShaderProgram._(this._glass, this._blurH, this._blurV);

  /// 着色器资产路径（库形态下位于 packages 包前缀内）。
  static const String glassAsset = 'shaders/liquid_glass.frag';
  static const String blurHorizontalAsset =
      'shaders/blur_horizontal.frag';
  static const String blurVerticalAsset =
      'shaders/blur_vertical.frag';

  final ui.FragmentProgram _glass;
  final ui.FragmentProgram _blurH;
  final ui.FragmentProgram _blurV;

  static GlassShaderProgram? _instance;
  static Future<GlassShaderProgram>? _loading;

  /// 是否已完成加载。
  static bool get isLoaded => _instance != null;

  /// 已加载的实例（未加载时抛出 [StateError]）。
  static GlassShaderProgram get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError('GlassShaderProgram.load() 尚未完成，请先在 main() 中 await。');
    }
    return inst;
  }

  /// 加载全部着色器（幂等，可重复调用）。
  static Future<GlassShaderProgram> load() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    return _loading ??= () async {
      final programs = await Future.wait<ui.FragmentProgram>([
        ui.FragmentProgram.fromAsset(glassAsset),
        ui.FragmentProgram.fromAsset(blurHorizontalAsset),
        ui.FragmentProgram.fromAsset(blurVerticalAsset),
      ]);
      _instance = GlassShaderProgram._(programs[0], programs[1], programs[2]);
      return _instance!;
    }();
  }

  /// 与 [load] 相同，语义上用于框架内部惰性加载。
  static Future<void> ensureLoaded() => load();

  /// 液态玻璃主着色器（折射 + 色散 + Fresnel + 光照）。
  ui.FragmentShader glassShader() => _glass.fragmentShader();

  /// 水平模糊 Pass 着色器。
  ui.FragmentShader blurHorizontalShader() => _blurH.fragmentShader();

  /// 垂直模糊 Pass 着色器。
  ui.FragmentShader blurVerticalShader() => _blurV.fragmentShader();
}
