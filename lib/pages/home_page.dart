import 'package:flutter/material.dart';

import 'package:liquid_glass_demo/glass/glass.dart';

/// 演示首页：单玻璃卡片 + 实时参数调节。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.profile});

  final GlassDeviceProfile profile;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double _refraction = 1.0;
  double _dispersion = 0.4;
  double _fresnel = 1.0;
  double _cornerRadius = 28.0;
  bool _animate = true;

  @override
  Widget build(BuildContext context) {
    final quality = widget.profile.quality;
    return Scaffold(
      body: LiquidGlassScene(
        quality: quality,
        builder: (context) {
          final handle = LiquidGlassScene.maybeOf(context);
          return Stack(
            children: [
              // ---- 状态与导航 ----
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QualityBadge(profile: widget.profile, handle: handle),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.topRight,
                          child: GlassFpsOverlay(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, top: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'TabBar 演示',
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/tabs'),
                          icon: const Icon(Icons.tab_rounded),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: '卡片列表演示',
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/cards'),
                          icon: const Icon(Icons.view_agenda_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ---- 中央玻璃卡片 ----
              Center(
                child: LiquidGlassWidget(
                  borderRadius: _cornerRadius,
                  refraction: _refraction,
                  dispersion: _dispersion,
                  fresnel: _fresnel,
                  animate: _animate,
                  onTap: () {},
                  child: Container(
                    width: 300,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.water_drop_outlined,
                            size: 44, color: Colors.white),
                        const SizedBox(height: 14),
                        const Text(
                          'Liquid Glass',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '折射 · 色散 · Fresnel 高光\n质量档位：${quality.name}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Switch(
                              value: _animate,
                              onChanged: (v) => setState(() => _animate = v),
                            ),
                            Text(
                              '液态波纹',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ---- 底部玻璃参数面板 ----
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: LiquidGlassWidget(
                      borderRadius: 22,
                      refraction: _refraction,
                      dispersion: _dispersion,
                      fresnel: _fresnel,
                      animate: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Slider(
                              label: '折射 Refraction',
                              value: _refraction,
                              min: 0,
                              max: 2.5,
                              onChanged: (v) => setState(() => _refraction = v),
                            ),
                            _Slider(
                              label: '色散 Dispersion',
                              value: _dispersion,
                              min: 0,
                              max: 1,
                              onChanged: (v) => setState(() => _dispersion = v),
                            ),
                            _Slider(
                              label: '边缘高光 Fresnel',
                              value: _fresnel,
                              min: 0,
                              max: 2,
                              onChanged: (v) => setState(() => _fresnel = v),
                            ),
                            _Slider(
                              label: '圆角 Radius',
                              value: _cornerRadius,
                              min: 8,
                              max: 64,
                              onChanged: (v) =>
                                  setState(() => _cornerRadius = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        // ---- 背景层：高对比度内容让折射/色散肉眼可见 ----
        background: const _HomeBackdrop(),
      ),
    );
  }
}

class _HomeBackdrop extends StatelessWidget {
  const _HomeBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            left: -40,
            child: _Blob(size: 220, color: const Color(0xFF667EEA)),
          ),
          Positioned(
            top: 120,
            right: -70,
            child: _Blob(size: 260, color: const Color(0xFFEB6396)),
          ),
          Positioned(
            bottom: 140,
            left: -30,
            child: _Blob(size: 180, color: const Color(0xFFF7971E)),
          ),
          Positioned(
            bottom: 60,
            right: 40,
            child: _Blob(size: 120, color: const Color(0xFF43E97B)),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 120),
                Text(
                  'GLASS BEHIND THIS CARD',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '观察边缘的折射与 RGB 色散分离',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.25)],
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.profile, required this.handle});

  final GlassDeviceProfile profile;
  final GlassSceneHandle? handle;

  @override
  Widget build(BuildContext context) {
    final q = handle?.quality ?? profile.quality;
    final sdk = profile.sdkInt == 0 ? '非 Android' : 'API ${profile.sdkInt}';
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCC1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$sdk · ${q.name.toUpperCase()}'
          '${profile.lowRamDevice ? ' · 低内存' : ''}',
          style: const TextStyle(color: Color(0xFFE8E8E8), fontSize: 11),
        ),
      ),
    );
  }
}
