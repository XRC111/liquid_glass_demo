<div align="center">

# Liquid Glass Demo · Flutter

**液态玻璃效果的完整示例程序 —— 真实折射、色散、边缘高光、触摸光照**

覆盖 Android API 24 → 35，低端设备自动降级。

[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.27-02569B?style=flat-square&logo=flutter)](https://flutter.dev/)
[![Platform](https://img.shields.io/badge/Platform-Android%20API%2024%2B-3DDC84?style=flat-square)](#兼容性)

</div>

---

> 配套组件库：[liquid_glass_library](https://github.com/XRC111/liquid_glass_library)（功能相同，已 package 化，可直接依赖）。
>
> 本仓库是**示例程序**，适合直接运行看效果、调参、对照着色器实现。

## 效果

| 特性 | 实现方式 |
| --- | --- |
| 真实折射 | 高度场（半球冠轮廓）+ 中心差分梯度求法线，边缘弯曲区产生像素级偏移 |
| RGB 色散 | R/G/B 三通道按不同折射系数分离采样，边缘出现彩虹分离 |
| 边缘高光 | Fresnel 反射项 `pow(1 - N·V, 3)` + 上缘亮线方向调制 |
| 触摸光照 | Blinn-Phong 高光跟随手指，高斯衰减半径约 90 px |
| 背景模糊 | 可分离高斯（水平 + 垂直两趟），1/4 分辨率离屏缓冲 |
| 液态波动 | 时间驱动的微波纹，产生轻微流动折射 |

## 运行

```bash
flutter pub get
flutter run                  # 连接 Android 设备/模拟器（API 24+）
flutter build apk --release  # 构建发布 APK
flutter analyze              # 静态检查
flutter test                 # 单元测试
```

要求 Flutter ≥ 3.27（推荐 3.35.x，仓库 CI 使用 3.35.7）。着色器在构建期由 Flutter 工具链编译为 Vulkan（SPIR-V）与 OpenGL ES 两套目标，运行时按后端自动选择。

## 三个演示页面

| 页面 | 内容 |
| --- | --- |
| 首页 | 单个玻璃卡片 + 参数滑块（折射/色散/Fresnel/模糊半径），实时预览 |
| TabBar 演示 | 悬浮玻璃底栏，折射下方滚动列表 |
| 卡片列表 | 多块玻璃卡片叠在图片背景上，观察相互遮挡与性能 |

## 兼容性

| API | 后端 | 档位 | 捕获分辨率 | 模糊 | 色散 | 折射 | 预期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 33+ | Impeller Vulkan | full | 0.5× | 1/4 分辨率 | 完整 | 完整 | ≥30 fps |
| 29–32 | Impeller Vulkan | full | 0.5× | 1/4 分辨率 | 完整 | 完整 | ≥30 fps |
| 26–28 | Impeller OpenGL ES | medium | 0.4× | 1/4 分辨率 | 简化 ×0.6 | ×0.85 | ≥25 fps |
| 24–25 | Impeller OpenGL ES | minimal | 0.3× | 跳过 | 关闭 | ×0.4 | 半透明兜底，不崩溃 |
| 低内存设备 | — | minimal | 0.3× | 跳过 | 关闭 | ×0.4 | 零离屏缓冲，不 OOM |

关键机制：

- **后端选择**：API 29+ 优先 Vulkan，24–28 回退 OpenGL ES 2.0；`AndroidManifest.xml` 中显式开启 `EnableImpeller`
- **Y 轴翻转**：OpenGL ES 纹理方向与 Vulkan 相反，三份着色器统一处理
- **降级兜底**：着色器加载失败或背景捕获失败时使用 `BackdropFilter`

## 项目结构

```
lib/
├── main.dart
├── glass/
│   ├── liquid_glass_widget.dart   # 核心玻璃组件 + 场景容器
│   ├── glass_shader_program.dart  # 着色器加载
│   └── glass_quality.dart         # 质量分级 + 设备检测
└── pages/
    ├── home_page.dart             # 单卡片 + 参数滑块
    ├── tabbar_demo.dart           # 底部 TabBar
    └── card_demo.dart             # 卡片列表
shaders/
├── liquid_glass.frag
├── blur_horizontal.frag
└── blur_vertical.frag
test/glass_quality_test.dart
```

## 常见陷阱

| 现象 | 原因 |
| --- | --- |
| 玻璃全黑 | 背景未包在 `RepaintBoundary` 内，捕获到空图 |
| 折射方向上下颠倒 | OpenGL ES 后端未做 Y 轴翻转 |
| 帧率骤降 | 捕获分辨率或模糊分辨率设得过大 |
| 低端机 OOM | 未按 `isLowRamDevice` 降级 |

## License

MIT（见 [LICENSE](./LICENSE)）
