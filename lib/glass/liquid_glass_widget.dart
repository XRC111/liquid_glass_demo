import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'glass_quality.dart';
import 'glass_shader_program.dart';

/// 无触摸时传给着色器的哨兵坐标（着色器内高斯衰减自然归零）。
const double _kNoTouch = -1.0e6;

/// 背景捕获刷新模式。
enum LiquidGlassRefreshMode {
  /// 每帧检测背景是否重绘，重绘时自动重新捕获（推荐，适配滚动/动画背景）。
  auto,

  /// 仅在尺寸或参数变化时捕获一次（完全静态背景的最省电模式）。
  onDemand,
}

/// 一帧可供玻璃面板采样的背景数据。
class GlassFrameData {
  const GlassFrameData({
    required this.background,
    required this.blurred,
    required this.bgSize,
    required this.quality,
  });

  /// 捕获的清晰背景（分辨率 = 逻辑尺寸 × captureScale）。
  final ui.Image? background;

  /// 1/4 分辨率模糊链输出（minimal 质量为 null）。
  final ui.Image? blurred;

  /// 背景对应的逻辑尺寸（清晰/模糊图共用同一逻辑坐标系）。
  final Size bgSize;

  /// 生成该帧数据时的质量分级。
  final GlassQuality quality;
}

/// 场景对外暴露的信息句柄（页面用它显示当前质量档位等）。
abstract interface class GlassSceneHandle {
  /// 当前生效的质量分级。
  GlassQuality get quality;

  /// 是否启用模糊 Pass。
  bool get usesBlur;

  /// 着色器与首帧背景是否就绪。
  bool get isReady;

  /// 自适应捕获降频档位（1=全速）。
  int get captureStride;
}

/// 场景内部代理（供玻璃 RenderObject 消费，不对外）。
abstract interface class GlassSceneDelegate {
  ValueListenable<GlassFrameData?> get frames;
  RenderRepaintBoundary? get backgroundBoundary;
}

/// 统计 paint 次数的 RepaintBoundary，用于零开销检测"背景是否重绘过"。
class _CountingRepaintBoundary extends RenderRepaintBoundary {
  int paintCount = 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    paintCount++;
    super.paint(context, offset);
  }
}

class _BoundaryCountingBox extends SingleChildRenderObjectWidget {
  const _BoundaryCountingBox({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _CountingRepaintBoundary();

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {}
}

/// 液态玻璃场景容器。
///
/// 负责：
/// 1. 用 [RepaintBoundary] 包裹背景层（[background]），通过
///    `RenderRepaintBoundary.toImageSync()`（[toImage] 的同步 GPU 版本）
///    捕获玻璃下方的像素；
/// 2. 在 1/4 分辨率离屏缓冲上执行水平 + 垂直两趟可分离高斯模糊；
/// 3. 把背景帧数据分发给场景内所有 [LiquidGlassWidget]；
/// 4. 根据设备能力（[GlassQuality]）自动调整捕获分辨率与模糊档位，
///    并在帧率下降时自适应降低捕获频率。
///
/// ```dart
/// LiquidGlassScene(
///   background: ColorfulBackdrop(),
///   builder: (context) => Center(
///     child: LiquidGlassWidget(child: Text('Liquid Glass')),
///   ),
/// )
/// ```
class LiquidGlassScene extends StatefulWidget {
  const LiquidGlassScene({
    super.key,
    required this.background,
    required this.builder,
    this.quality,
    this.captureScale,
    this.blurScale = 0.25,
    this.blurRadius = 14.0,
    this.refreshMode = LiquidGlassRefreshMode.auto,
  });

  /// 位于玻璃下方的背景内容（会被捕获并参与折射/模糊）。
  final Widget background;

  /// 场景内容构建器，在背景之上叠加玻璃面板等 UI。
  final WidgetBuilder builder;

  /// 手动指定质量分级（null 时按设备能力自动分级）。
  final GlassQuality? quality;

  /// 背景捕获分辨率系数（null 时按质量档位取默认值）。
  final double? captureScale;

  /// 模糊缓冲分辨率系数，0.25 表示模糊 Pass 在 1/4 分辨率上执行。
  final double blurScale;

  /// 模糊半径（逻辑像素）。
  final double blurRadius;

  /// 背景捕获刷新模式。
  final LiquidGlassRefreshMode refreshMode;

  @override
  State<LiquidGlassScene> createState() => _LiquidGlassSceneState();

  /// 从 [context] 向上查找场景信息句柄。
  static GlassSceneHandle? maybeOf(BuildContext context) {
    final scope = context.findAncestorWidgetOfExactType<_SceneScope>();
    return scope?.state;
  }
}

class _LiquidGlassSceneState extends State<LiquidGlassScene>
    implements GlassSceneHandle, GlassSceneDelegate {
  final GlobalKey _bgKey = GlobalKey(debugLabel: 'LiquidGlassScene.background');
  final ValueNotifier<GlassFrameData?> _frames = ValueNotifier<GlassFrameData?>(null);

  GlassShaderProgram? _shaders;
  GlassQuality _quality = GlassQuality.minimal;
  bool _ready = false;

  ui.Image? _bgImage;
  ui.Image? _blurred;
  Size _bgSize = Size.zero;
  int _lastPaintCount = -1;
  bool _captureQueued = false;
  bool _needsCapture = true;

  // 自适应捕获降频（低端设备帧率不足时降低捕获频率而非帧率）
  int _stride = 1;
  int _frameCounter = 0;
  Duration _lastTimestamp = Duration.zero;
  double _avgFrameMs = 16.7;

  @override
  GlassQuality get quality => _quality;

  @override
  bool get usesBlur => _quality.usesBlur;

  @override
  bool get isReady => _ready;

  @override
  int get captureStride => _stride;

  @override
  ValueListenable<GlassFrameData?> get frames => _frames;

  @override
  RenderRepaintBoundary? get backgroundBoundary =>
      _bgKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

  @override
  void initState() {
    super.initState();
    _shaders = GlassShaderProgram.isLoaded ? GlassShaderProgram.instance : null;
    if (_shaders == null) {
      GlassShaderProgram.load().then((_) {
        if (mounted) {
          setState(() => _shaders = GlassShaderProgram.instance);
        }
      });
    }
    _resolveQuality();
  }

  Future<void> _resolveQuality() async {
    if (widget.quality != null) {
      if (mounted) {
        setState(() {
          _quality = widget.quality!;
          _needsCapture = true;
        });
      }
      return;
    }
    final profile = await GlassDeviceProfile.detect();
    if (mounted) {
      setState(() {
        _quality = profile.quality;
        _needsCapture = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant LiquidGlassScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quality != widget.quality) {
      _quality = widget.quality ?? _quality;
      _needsCapture = true;
      if (widget.quality == null) _resolveQuality();
    }
    if (oldWidget.captureScale != widget.captureScale ||
        oldWidget.blurScale != widget.blurScale ||
        oldWidget.blurRadius != widget.blurRadius) {
      _needsCapture = true;
    }
    _queueCapture();
  }

  /// 在每帧渲染结束后排队一次捕获（依赖帧驱动，静止时零开销）。
  void _queueCapture() {
    if (_captureQueued) return;
    if (widget.refreshMode == LiquidGlassRefreshMode.onDemand && !_needsCapture) {
      return;
    }
    _captureQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _captureQueued = false;
      if (!mounted) return;
      _onPostFrame();
    });
  }

  void _onPostFrame() {
    // ---- 帧率自适应：捕获降频而非整体掉帧 ----
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (now > _lastTimestamp) {
      final deltaMs = (now - _lastTimestamp).inMicroseconds / 1000.0;
      if (deltaMs < 500) {
        _avgFrameMs = _avgFrameMs * 0.9 + deltaMs * 0.1;
      }
      _lastTimestamp = now;
    }
    if (_avgFrameMs > 40 && _stride < 4) {
      _stride++; // < 25fps：降低捕获频率
    } else if (_avgFrameMs < 22 && _stride > 1) {
      _stride--; // > 45fps：恢复全速
    }

    _frameCounter++;
    if (_frameCounter % _stride == 0) {
      _capture();
    }
    _queueCapture(); // everyFrame 模式继续跟随帧驱动
  }

  void _capture() {
    final boundary = _bgKey.currentContext?.findRenderObject();
    if (boundary is! _CountingRepaintBoundary || !boundary.attached) return;
    final logicalSize = boundary.size;
    if (logicalSize.isEmpty) return;

    final paintCount = boundary.paintCount;
    final sizeChanged = logicalSize != _bgSize;
    final firstRun = _bgImage == null;
    if (widget.refreshMode == LiquidGlassRefreshMode.onDemand) {
      if (!_needsCapture && !sizeChanged && !firstRun) return;
      _needsCapture = false;
    } else {
      // 背景层未重绘且尺寸未变：无需重新捕获
      if (paintCount == _lastPaintCount && !sizeChanged && !firstRun) return;
    }
    _lastPaintCount = paintCount;

    try {
      final scale =
          (widget.captureScale ?? _quality.captureScale).clamp(0.1, 1.0);
      // RepaintBoundary + toImageSync：同步拿到 GPU 纹理（toImage 的零拷贝变体）
      final img = boundary.toImageSync(pixelRatio: scale);
      final oldBg = _bgImage;
      _bgImage = img;
      oldBg?.dispose();

      final shaders = _shaders;
      final oldBlurred = _blurred;
      if (shaders != null && _quality.usesBlur) {
        _blurred = _runBlurChain(shaders, img);
      } else {
        _blurred = null; // minimal：跳过模糊 Pass，零离屏缓冲
      }
      oldBlurred?.dispose();

      _bgSize = logicalSize;
      _ready = true;
      _frames.value = GlassFrameData(
        background: _bgImage,
        blurred: _blurred,
        bgSize: _bgSize,
        quality: _quality,
      );
    } catch (_) {
      // 首帧 boundary 尚未完成绘制等瞬态错误，下一帧自动重试
    }
  }

  /// 模糊链：下采样 -> 水平 Pass -> 垂直 Pass，全程在 1/4 分辨率缓冲执行。
  ui.Image? _runBlurChain(GlassShaderProgram shaders, ui.Image src) {
    final w =
        ((_bgSize.width * widget.blurScale).round().clamp(1, 2048)).toDouble();
    final h = ((_bgSize.height * widget.blurScale).round().clamp(1, 2048))
        .toDouble();
    final radiusPx = (widget.blurRadius * widget.blurScale).clamp(0.5, 8.0);

    // 1) 捕获图下采样到模糊缓冲分辨率
    final down = _renderToImage(w, h, (canvas, size) {
      final srcRect = Rect.fromLTWH(
          0, 0, src.width.toDouble(), src.height.toDouble());
      canvas.drawImageRect(
        src,
        srcRect,
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.low,
      );
    });
    if (down == null) return null;

    // 2) 水平模糊 Pass
    final horizontal = _renderToImage(w, h, (canvas, size) {
      final s = shaders.blurHorizontalShader();
      s.setFloat(0, size.width);
      s.setFloat(1, size.height);
      s.setFloat(2, radiusPx);
      s.setImageSampler(0, down);
      canvas.drawRect(Offset.zero & size, Paint()..shader = s);
    });
    down.dispose();
    if (horizontal == null) return null;

    // 3) 垂直模糊 Pass
    final vertical = _renderToImage(w, h, (canvas, size) {
      final s = shaders.blurVerticalShader();
      s.setFloat(0, size.width);
      s.setFloat(1, size.height);
      s.setFloat(2, radiusPx);
      s.setImageSampler(0, horizontal);
      canvas.drawRect(Offset.zero & size, Paint()..shader = s);
    });
    horizontal.dispose();
    return vertical;
  }

  ui.Image? _renderToImage(double w, double h, void Function(ui.Canvas, ui.Size) draw) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    draw(canvas, ui.Size(w, h));
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(w.round(), h.round());
    } catch (_) {
      return null;
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    _queueCapture();
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: _bgKey, child: _BoundaryCountingBox(child: widget.background)),
        _SceneScope(state: this, child: Builder(builder: widget.builder)),
      ],
    );
  }

  @override
  void dispose() {
    _frames.dispose();
    _bgImage?.dispose();
    _blurred?.dispose();
    super.dispose();
  }
}

class _SceneScope extends InheritedWidget {
  const _SceneScope({required this.state, required super.child});

  final _LiquidGlassSceneState state;

  @override
  bool updateShouldNotify(_SceneScope oldWidget) => false;
}

/// 玻璃面板视觉参数。
class GlassParams {
  const GlassParams({
    required this.borderRadius,
    required this.refraction,
    required this.dispersion,
    required this.fresnel,
    required this.opacity,
  });

  final double borderRadius;
  final double refraction;
  final double dispersion;
  final double fresnel;
  final double? opacity;

  @override
  bool operator ==(Object other) =>
      other is GlassParams &&
      other.borderRadius == borderRadius &&
      other.refraction == refraction &&
      other.dispersion == dispersion &&
      other.fresnel == fresnel &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(borderRadius, refraction, dispersion, fresnel, opacity);
}

/// 液态玻璃面板组件。
///
/// 必须放在 [LiquidGlassScene] 内部才有真实折射；脱离场景时自动退化为
/// 半透明 + 边缘高光的静态样式（不崩溃）。
class LiquidGlassWidget extends StatefulWidget {
  const LiquidGlassWidget({
    super.key,
    this.child,
    this.borderRadius = 24.0,
    this.refraction = 1.0,
    this.dispersion = 0.4,
    this.fresnel = 1.0,
    this.opacity,
    this.animate = true,
    this.onTap,
  });

  /// 玻璃内容（绘制在折射效果之上）。
  final Widget? child;

  /// 圆角半径（SDF 形状定义）。
  final double borderRadius;

  /// 折射强度（>0 启用高度场折射；minimal 质量会自动减弱）。
  final double refraction;

  /// RGB 色散强度 0-1（minimal 质量强制为 0）。
  final double dispersion;

  /// Fresnel 边缘高光强度。
  final double fresnel;

  /// 整体不透明度（null 时按质量档位取默认值）。
  final double? opacity;

  /// 是否启用液态微波纹动画（false 时仅在触摸/背景变化时重绘，更省电）。
  final bool animate;

  /// 点击回调。
  final VoidCallback? onTap;

  @override
  State<LiquidGlassWidget> createState() => _LiquidGlassWidgetState();
}

class _LiquidGlassWidgetState extends State<LiquidGlassWidget>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _time = 0;
  RenderLiquidGlass? _renderObject;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.animate && _ticker == null) {
      _ticker = createTicker((elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        if (t - _time < 1 / 120) return;
        _time = t;
        _renderObject?.markNeedsPaint();
      });
      _ticker!.start();
    } else if (!widget.animate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget glass = _GlassBox(
      timeOf: () => _time,
      params: GlassParams(
        borderRadius: widget.borderRadius,
        refraction: widget.refraction,
        dispersion: widget.dispersion,
        fresnel: widget.fresnel,
        opacity: widget.opacity,
      ),
      onTap: widget.onTap,
      child: widget.child,
    );
    glass = Listener(
      onPointerDown: (event) => _renderObject?.touch = event.localPosition,
      onPointerMove: (event) => _renderObject?.touch = event.localPosition,
      onPointerUp: (_) => _renderObject?.touch = const Offset(_kNoTouch, _kNoTouch),
      onPointerCancel: (_) => _renderObject?.touch = const Offset(_kNoTouch, _kNoTouch),
      child: glass,
    );
    if (widget.onTap != null) {
      glass = GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: glass,
      );
    }
    return glass;
  }
}

class _GlassBox extends SingleChildRenderObjectWidget {
  const _GlassBox({
    super.child,
    required this.params,
    required this.timeOf,
    required this.onTap,
  });

  final GlassParams params;
  final double Function() timeOf;
  final VoidCallback? onTap;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final delegate =
        context.findAncestorWidgetOfExactType<_SceneScope>()?.state;
    final ro = RenderLiquidGlass(params: params, delegate: delegate, timeOf: timeOf);
    // 让 Listener 闭包能定位到 RenderObject（避免每帧 findRenderObject）
    final state = context.findAncestorStateOfType<_LiquidGlassWidgetState>();
    state?._renderObject = ro;
    return ro;
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderLiquidGlass renderObject) {
    renderObject
      ..params = params
      ..timeOf = timeOf
      ..delegate =
          context.findAncestorWidgetOfExactType<_SceneScope>()?.state;
    renderObject.onTap = onTap;
  }
}

/// 液态玻璃渲染对象。
///
/// paint 时将自身相对背景 RepaintBoundary 的位置与全部 uniform 一起送入
/// FragmentShader，一次 drawRect 完成折射 + 色散 + Fresnel + 动态光照。
class RenderLiquidGlass extends RenderProxyBox {
  RenderLiquidGlass({
    GlassParams? params,
    GlassSceneDelegate? delegate,
    double Function()? timeOf,
  })  : _params = params ??
            const GlassParams(
              borderRadius: 24,
              refraction: 1,
              dispersion: 0.4,
              fresnel: 1,
              opacity: null,
            ),
        _delegate = delegate,
        _timeOf = timeOf;

  static const double _noTouch = _kNoTouch;

  GlassParams _params;
  GlassSceneDelegate? _delegate;
  double Function()? _timeOf;
  Offset _touch = const Offset(_noTouch, _noTouch);
  VoidCallback? onTap;

  set params(GlassParams value) {
    if (_params == value) return;
    _params = value;
    markNeedsPaint();
  }

  set timeOf(double Function()? value) => _timeOf = value;

  set delegate(GlassSceneDelegate? value) {
    if (_delegate == value) return;
    _delegate?.frames.removeListener(_onFrame);
    _delegate = value;
    value?.frames.addListener(_onFrame);
    markNeedsPaint();
  }

  set touch(Offset value) {
    if (_touch == value) return;
    _touch = value;
    markNeedsPaint();
  }

  void _onFrame() => markNeedsPaint();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _delegate?.frames.addListener(_onFrame);
  }

  @override
  void detach() {
    _delegate?.frames.removeListener(_onFrame);
    super.detach();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final delegate = _delegate;
    final frame = delegate?.frames.value;
    final shaders =
        GlassShaderProgram.isLoaded ? GlassShaderProgram.instance : null;

    if (shaders == null || delegate == null || frame == null || frame.background == null) {
      _paintFallback(canvas, offset);
      if (child != null) context.paintChild(child!, offset);
      return;
    }

    // 质量分档决定采样纹理：full/medium 用模糊图，minimal 用清晰图
    final quality = frame.quality;
    final ui.Image image =
        (quality.usesBlur && frame.blurred != null) ? frame.blurred! : frame.background!;

    // 自身左上角在背景逻辑坐标系中的位置
    Offset localInBg = Offset.zero;
    final bgBoundary = delegate.backgroundBoundary;
    if (bgBoundary != null && bgBoundary.attached && attached) {
      try {
        localInBg = localToGlobal(Offset.zero, ancestor: bgBoundary);
      } catch (_) {
        localInBg = Offset.zero;
      }
    }

    final shader = shaders.glassShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, frame.bgSize.width)
      ..setFloat(3, frame.bgSize.height)
      ..setFloat(4, localInBg.dx)
      ..setFloat(5, localInBg.dy)
      ..setFloat(6, _params.borderRadius)
      ..setFloat(7, _params.refraction * quality.refractionScale)
      ..setFloat(8, quality.usesDispersion
          ? _params.dispersion * quality.dispersionScale
          : 0.0)
      ..setFloat(9, _params.fresnel)
      ..setFloat(10, _touch.dx)
      ..setFloat(11, _touch.dy)
      ..setFloat(12, _timeOf?.call() ?? 0.0)
      ..setFloat(13, _params.opacity ?? quality.defaultOpacity)
      ..setImageSampler(0, image);

    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..drawRect(Offset.zero & size, Paint()..shader = shader)
      ..restore();

    if (child != null) context.paintChild(child!, offset);
  }

  /// 无场景/着色器未就绪时的静态退化样式：半透明 + 边缘高光。
  void _paintFallback(ui.Canvas canvas, Offset offset) {
    final opacity = _params.opacity ?? GlassQuality.minimal.defaultOpacity;
    final rrect = RRect.fromRectAndRadius(
      offset & size,
      Radius.circular(_params.borderRadius),
    );
    canvas
      ..drawRRect(
        rrect,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.14 * opacity),
      )
      ..drawRRect(
        rrect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.38 * opacity),
      );
  }
}
