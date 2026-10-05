import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'liquid_glass_widget.dart';

/// 简易帧率统计浮层，用于性能验收（目标：full/medium ≥ 30fps）。
///
/// 放置在页面任意角落即可，不影响玻璃渲染管线：
///
/// ```dart
/// const Align(alignment: Alignment.topRight, child: GlassFpsOverlay()),
/// ```
class GlassFpsOverlay extends StatefulWidget {
  const GlassFpsOverlay({super.key, this.showQualityBadge = true});

  final bool showQualityBadge;

  @override
  State<GlassFpsOverlay> createState() => _GlassFpsOverlayState();
}

class _GlassFpsOverlayState extends State<GlassFpsOverlay>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  int _frames = 0;
  Duration _lastSample = Duration.zero;
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _frames++;
      if (elapsed - _lastSample >= const Duration(milliseconds: 500)) {
        final seconds = elapsed.inMicroseconds / 1e6;
        setState(() {
          _fps = _frames / (seconds - _lastSample.inMicroseconds / 1e6);
        });
        _lastSample = elapsed;
        _frames = 0;
      }
    });
    _ticker!.start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quality = LiquidGlassScene.maybeOf(context)?.quality;
    final label = _fps.toStringAsFixed(0);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xCC1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          widget.showQualityBadge && quality != null
              ? 'FPS $label · ${quality.name.toUpperCase()}'
              : 'FPS $label',
          style: const TextStyle(
            color: Color(0xFFE8E8E8),
            fontSize: 11,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
