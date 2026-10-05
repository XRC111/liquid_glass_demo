import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 液态玻璃渲染质量分级。
///
/// 对应 Android 图形 API 分层：
/// ```
/// full     → API 29+  → Impeller Vulkan    全分辨率 + 色散 + 动态光照
/// medium   → API 26-28 → Impeller OpenGL ES 1/2 分辨率捕获 + 简化色散
/// minimal  → API 24-25 / 低内存 → 跳过模糊, 仅半透明 + 边缘高光
/// ```
enum GlassQuality {
  /// API 29+：全分辨率捕获、完整折射 + 色散 + 触摸动态光照 + 模糊。
  full,

  /// API 26-28：降低捕获分辨率、简化色散系数、保留模糊。
  medium,

  /// API 24-25 或低内存设备（isLowRamDevice）：跳过模糊 Pass，
  /// 折射减弱、无色散、整体半透明，仅保留边缘高光。
  minimal;

  /// 由设备信息推导质量分级（核心降级策略）。
  static GlassQuality fromDevice({
    required int sdkInt,
    required bool lowRamDevice,
  }) {
    if (lowRamDevice || sdkInt < 26) {
      return GlassQuality.minimal;
    }
    if (sdkInt < 29) {
      return GlassQuality.medium;
    }
    return GlassQuality.full;
  }

  /// 是否启用模糊 Pass（minimal 跳过模糊，零离屏缓冲）。
  bool get usesBlur => this != GlassQuality.minimal;

  /// 是否启用 RGB 色散（minimal 关闭，medium 使用简化系数）。
  bool get usesDispersion => this != GlassQuality.minimal;

  /// 色散系数乘数（medium 简化色散）。
  double get dispersionScale => this == GlassQuality.full ? 1.0 : 0.6;

  /// 折射强度乘数（minimal 减弱折射以规避低端 GPU 带宽压力）。
  double get refractionScale =>
      this == GlassQuality.full ? 1.0 : (this == GlassQuality.medium ? 0.85 : 0.4);

  /// 背景捕获分辨率系数（相对逻辑像素）。
  double get captureScale =>
      this == GlassQuality.full ? 0.5 : (this == GlassQuality.medium ? 0.4 : 0.3);

  /// 建议的整体不透明度（minimal 依靠半透明表达玻璃感）。
  double get defaultOpacity => this == GlassQuality.minimal ? 0.72 : 1.0;
}

/// 设备能力信息，用于自动质量分级。
class GlassDeviceProfile {
  const GlassDeviceProfile({
    required this.sdkInt,
    required this.lowRamDevice,
    required this.quality,
  });

  /// Android API level（非 Android 平台为 0）。
  final int sdkInt;

  /// 是否低内存设备（ActivityManager.isLowRamDevice）。
  final bool lowRamDevice;

  /// 自动推导的质量分级。
  final GlassQuality quality;

  static const MethodChannel _channel = MethodChannel('liquid_glass/device_info');
  static GlassDeviceProfile? _cached;

  /// 检测设备能力（结果缓存）。
  ///
  /// - Android：通过 MethodChannel 读取 Build.VERSION.SDK_INT 与
  ///   ActivityManager.isLowRamDevice。
  /// - 非 Android 平台（iOS/macOS/Windows/Linux）：直接使用 full 档。
  /// - 检测失败：按当前 Flutter 模板下限（API 24 → minimal）保守回退，
  ///   保证低端设备不崩溃；app 启动后可用 [GlassQualityOverride] 修正。
  static Future<GlassDeviceProfile> detect() async {
    final cached = _cached;
    if (cached != null) return cached;

    int sdkInt = 0;
    bool lowRam = false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final raw = await _channel.invokeMapMethod<String, Object?>('getDeviceInfo');
        sdkInt = (raw?['sdkInt'] as num?)?.toInt() ?? 0;
        lowRam = raw?['lowRam'] as bool? ?? false;
      } on MissingPluginException {
        // 非 Android 运行环境或宿主未实现通道
      } on PlatformException {
        // 通道异常：按最低档保守处理
      }
    }

    final quality = sdkInt == 0 && defaultTargetPlatform != TargetPlatform.android
        ? GlassQuality.full
        : GlassQuality.fromDevice(
            sdkInt: sdkInt == 0 ? 24 : sdkInt,
            lowRamDevice: lowRam,
          );
    _cached = GlassDeviceProfile(
      sdkInt: sdkInt,
      lowRamDevice: lowRam,
      quality: quality,
    );
    return _cached!;
  }
}
