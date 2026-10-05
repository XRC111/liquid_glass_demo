import 'package:flutter/material.dart';

import 'package:liquid_glass_demo/glass/glass.dart';

/// 卡片列表演示：玻璃 AppBar 悬浮，滚动内容实时从玻璃下方穿过，
/// 验证滚动场景下背景捕获 + 模糊链的实时性与帧率。
class CardDemo extends StatefulWidget {
  const CardDemo({super.key, required this.profile});

  final GlassDeviceProfile profile;

  @override
  State<CardDemo> createState() => _CardDemoState();
}

class _CardDemoState extends State<CardDemo> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LiquidGlassScene(
        quality: widget.profile.quality,
        refreshMode: LiquidGlassRefreshMode.auto,
        builder: (context) {
          return Stack(
            children: [
              // ---- 顶部玻璃 AppBar ----
              Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: LiquidGlassWidget(
                      borderRadius: 22,
                      refraction: 1.0,
                      dispersion: 0.4,
                      fresnel: 1.0,
                      animate: false,
                      child: Container(
                        height: 58,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                            ),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text(
                                'Glass Cards',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.search, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.topRight,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(top: 78, right: 14),
                    child: GlassFpsOverlay(),
                  ),
                ),
              ),
            ],
          );
        },
        // ---- 背景层：卡片列表本体（滚动时实时穿过玻璃 AppBar 下方） ----
        background: Container(
          color: const Color(0xFF101418),
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 90, 16, 30),
            itemCount: 40,
            itemBuilder: (context, i) {
              final hue = (i * 29) % 360;
              return Container(
                height: 120,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      HSLColor.fromAHSL(1, hue.toDouble(), 0.65, 0.55).toColor(),
                      HSLColor.fromAHSL(
                              1, (hue + 55) % 360.0, 0.65, 0.38).toColor(),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Card #${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '滚动列表 · 内容穿过玻璃时产生折射、色散与模糊',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
