import 'package:flutter/material.dart';

import 'package:liquid_glass_demo/glass/glass.dart';

/// 底部 TabBar 演示：玻璃 TabBar 悬浮于滚动内容之上。
class TabBarDemo extends StatefulWidget {
  const TabBarDemo({super.key, required this.profile});

  final GlassDeviceProfile profile;

  @override
  State<TabBarDemo> createState() => _TabBarDemoState();
}

class _TabBarDemoState extends State<TabBarDemo> {
  int _index = 0;

  static const _tabs = [
    (icon: Icons.home_outlined, label: '首页'),
    (icon: Icons.explore_outlined, label: '发现'),
    (icon: Icons.favorite_border, label: '收藏'),
    (icon: Icons.person_outline, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LiquidGlassScene(
        quality: widget.profile.quality,
        builder: (context) {
          return Stack(
            children: [
              const Align(
                alignment: Alignment.topCenter,
                child: SafeArea(child: GlassFpsOverlay()),
              ),
              // ---- 顶部玻璃标题条 ----
              Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: LiquidGlassWidget(
                      borderRadius: 20,
                      refraction: 1.0,
                      dispersion: 0.4,
                      fresnel: 1.0,
                      animate: false,
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _tabs[_index].label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ---- 底部玻璃 TabBar ----
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: LiquidGlassWidget(
                      borderRadius: 26,
                      refraction: 1.1,
                      dispersion: 0.5,
                      fresnel: 1.2,
                      animate: true,
                      child: Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            for (var i = 0; i < _tabs.length; i++)
                              Expanded(
                                child: _TabItem(
                                  icon: _tabs[i].icon,
                                  label: _tabs[i].label,
                                  selected: i == _index,
                                  onTap: () => setState(() => _index = i),
                                ),
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
        // ---- 背景层：随 Tab 切换的内容（滚动时玻璃实时折射内容） ----
        background: _TabBackdrop(index: _index),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Colors.white.withValues(alpha: 0.62);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}

/// 每个 Tab 一组彩色渐变内容，滚动时穿过玻璃下方。
class _TabBackdrop extends StatelessWidget {
  const _TabBackdrop({required this.index});

  final int index;

  static const _palettes = [
    [Color(0xFF355C7D), Color(0xFF6C5B7B), Color(0xFFC06C84)],
    [Color(0xFF134E5E), Color(0xFF71B280)],
    [Color(0xFF42275A), Color(0xFF734B6D)],
    [Color(0xFF16222A), Color(0xFF3A6073)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[index % _palettes.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 110, 16, 120),
        itemCount: 24,
        itemBuilder: (context, i) {
          final hue = (i * 47 + index * 90) % 360;
          return Container(
            height: 86,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  HSLColor.fromAHSL(1, hue.toDouble(), 0.72, 0.62).toColor(),
                  HSLColor.fromAHSL(1, (hue + 40) % 360.0, 0.72, 0.5).toColor(),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Tab $index · 色块 #${i + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          );
        },
      ),
    );
  }
}
