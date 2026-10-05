# Liquid Glass Demo（Flutter 液态玻璃示例程序）

基于 Flutter `FragmentProgram` 自定义片元着色器实现的**液态玻璃（Liquid Glass）**效果示例：真实折射、RGB 色散分离、Fresnel 边缘高光、触摸动态光照，覆盖 **Android API 24 → 35** 全版本兼容，低端设备自动降级。

配套 Flutter 组件库：[liquid_glass_flutter](https://github.com/XRC111/liquid_glass_flutter)（功能相同，package 化，可直接依赖）。

---

## 效果

| 特性 | 实现方式 |
| --- | --- |
| 真实折射 | 高度场（半球冠轮廓）+ 中心差分梯度求法线，边缘弯曲区产生像素级折射偏移 |
| RGB 色散 | R/G/B 三通道按不同折射系数分离采样，边缘出现彩虹色分离 |
| 边缘高光 | Fresnel 反射项（`pow(1 - N·V, 3)`）+ 上缘亮线方向调制 |
| 触摸光照 | Blinn-Phong 高光跟随手指，高斯衰减半径 ~90px |
| 背景模糊 | 可分离高斯模糊（水平 + 垂直两趟 11-tap），在 **1/4 分辨率**离屏缓冲执行 |
| 液态波动 | 时间驱动的微波纹，让玻璃内部产生轻微流动折射 |

## 项目结构

```
liquid_glass_demo/
├── lib/
│   ├── main.dart
│   ├── glass/
│   │   ├── liquid_glass_widget.dart      # 核心玻璃组件 + 场景容器
│   │   ├── glass_shader_program.dart     # 着色器加载管理
│   │   └── glass_quality.dart            # 质量分级枚举 + 设备检测
│   └── pages/
│       ├── home_page.dart                 # 演示首页（单卡片 + 参数滑块）
│       ├── tabbar_demo.dart               # 底部 TabBar 演示
│       └── card_demo.dart                 # 卡片列表演示
├── shaders/
│   ├── liquid_glass.frag                  # 液态玻璃片元着色器
│   ├── blur_horizontal.frag               # 水平模糊 Pass
│   └── blur_vertical.frag                 # 垂直模糊 Pass
├── android/
│   └── app/build.gradle.kts               # minSdk 24 / targetSdk 35
├── test/glass_quality_test.dart           # 质量分级单元测试
├── pubspec.yaml
└── README.md
```

## 运行

```bash
flutter pub get
flutter run                 # 连接 Android 设备/模拟器（API 24+）
flutter build apk --release # 构建发布 APK
flutter analyze             # 静态检查（当前 0 警告）
flutter test                # 单元测试
```

要求 Flutter ≥ 3.27（推荐 3.35.x，本仓库 CI 使用 3.35.7）。着色器在构建期由 Flutter 工具链同时编译为 Vulkan（SPIR-V）与 OpenGL ES 两套目标，运行时按设备后端自动选择。

## API 级别降级表现

| API | 后端 | 质量档位 | 捕获分辨率 | 模糊 | 色散 | 折射 | 预期表现 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 33+（含 Android 15/16） | Impeller Vulkan | `full` | 0.5× | ✅ 1/4 分辨率 | ✅ 完整 | ✅ 完整 | 完整折射 + 色散 + 动态光照，≥ 30fps |
| 29-32 | Impeller Vulkan | `full` | 0.5× | ✅ 1/4 分辨率 | ✅ 完整 | ✅ 完整 | Vulkan 后端启用，≥ 30fps |
| 26-28 | Impeller OpenGL ES | `medium` | 0.4× | ✅ 1/4 分辨率 | ⚠️ 简化（×0.6） | ⚠️ ×0.85 | ≥ 25fps |
| 24-25 | Impeller OpenGL ES | `minimal` | 0.3× | ❌ 跳过 | ❌ 关闭 | ⚠️ ×0.4 | 半透明 + 边缘高光，不崩溃 |
| 任意 API + `isLowRamDevice=true` | — | `minimal` | 0.3× | ❌ 跳过 | ❌ 关闭 | ⚠️ ×0.4 | 低内存设备不 OOM，零离屏模糊缓冲 |

关键机制：

- **后端选择**：Impeller 在 API 29+ 优先 Vulkan（依赖 `VK_ANDROID_external_memory_android_hardware_buffer`），API 24-28 自动回退 OpenGL ES 2.0；`AndroidManifest.xml` 中显式设置 `io.flutter.embedding.android.EnableImpeller=true`。
- **Y 轴翻转**：OpenGL ES 后端纹理方向与 Vulkan 相反，三份着色器统一通过
  `#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)` 处理采样翻转，新版引擎改为 top-down 后由宏自动跳过。
- **设备检测**：`MainActivity.kt` 通过 MethodChannel 上报 `Build.VERSION.SDK_INT` 与 `ActivityManager.isLowRamDevice`，`GlassQuality.fromDevice()` 推导档位。
- **自适应降频**：帧率 < 25fps 时自动降低背景捕获频率（每 2~4 帧一次）而非整体掉帧；> 45fps 时恢复全速。

## 核心代码

```dart
// 加载着色器（构建期已编译为双后端目标）
final program = await FragmentProgram.fromAsset('shaders/liquid_glass.frag');
final shader = program.fragmentShader();

// 设置 uniforms + 背景 sampler
shader.setFloat(0, size.width);
shader.setFloat(1, size.height);
shader.setFloat(2, touchX);
shader.setFloat(3, touchY);
shader.setImageSampler(0, backgroundImage);

// 绘制
canvas.drawRect(rect, Paint()..shader = shader);
```

背景捕获采用 `RepaintBoundary` + `RenderRepaintBoundary.toImageSync()`（`toImage()` 的同步 GPU 变体，避免每帧异步开销），玻璃通过 SDF 圆角矩形裁剪出玻璃形状并对背景做折射采样。

## 三个演示页面

| 页面 | 内容 | 验证点 |
| --- | --- | --- |
| 首页（`/`） | 渐变背景 + 中央玻璃卡片 + 实时参数滑块（折射/色散/边缘光/圆角） | 静态场景折射效果、参数联动、质量徽章 |
| TabBar 演示（`/tabs`） | 玻璃底部 TabBar + 玻璃标题条，4 个 Tab 内容可滚动 | 触摸高光跟随手指、内容滚动穿过玻璃 |
| 卡片列表（`/cards`） | 40 张彩色卡片列表 + 悬浮玻璃 AppBar | 滚动场景实时捕获 + 模糊链帧率 |

页面右上角内置 **FPS 浮层**（如 `FPS 60 · FULL`），可直接在真机上进行性能验收。

## 性能测试报告

### 设计性能预算（按质量档位）

| 档位 | 每帧 GPU 工作量 | 预算估算 |
| --- | --- | --- |
| full | 0.5× 捕获 + 2 × 1/8 分辨率 11-tap 模糊 Pass + 1 次全屏玻璃 Pass | 1080p 设备上捕获 + 模糊合计 < 2.5ms，玻璃 Pass < 1.5ms |
| medium | 0.4× 捕获 + 模糊（同分辨率 1/4） | 合计 < 2ms |
| minimal | 0.3× 捕获 + 1 次玻璃 Pass（无模糊） | 合计 < 1ms |

### 实测方法（真机验收）

1. 安装 release APK：`flutter build apk --release`；
2. 打开各演示页，观察右上角 FPS 浮层（500ms 采样窗口）；
3. 滚动卡片列表页 / 切换 Tab，记录稳态 FPS；
4. 对照验收标准：

| 验收项 | 目标 |
| --- | --- |
| API 33+ 设备 | 完整折射 + 色散 + 动态光照，帧率 ≥ 30fps |
| API 29-32 设备 | Vulkan 后端启用（`flutter run -v` 日志可见 Impeller Vulkan），帧率 ≥ 30fps |
| API 26-28 设备 | OpenGL ES 后端，帧率 ≥ 25fps |
| API 24-25 设备 | 自动降级 minimal，不崩溃 |
| 低内存设备（isLowRamDevice） | 不 OOM，自动跳过模糊 |
| 触摸玻璃 | 边缘高光跟随手指移动 |
| `flutter analyze` | 0 警告（本仓库当前状态即满足） |

> 注：绝对帧率取决于具体 SoC/GPU 与分辨率，上表预算为中端机型（Adreno 6xx 级）的工程估算。实机数据请按上述方法在真机上用内置 FPS 浮层采集；所有降级路径（minimal 跳过模糊、低内存回退、自适应降频）均为代码内自动行为，无需手动配置。

## 常见陷阱对照

- ✅ minSdk 24（Flutter 3.35 模板默认值，非 API 21）
- ✅ Impeller GLES 后端 Y 轴翻转已处理，新版 top-down 由宏兼容
- ✅ 低内存设备强制 minimal，避免 OOM
- ✅ Android 7-9（Vulkan 驱动不完善）不走 Vulkan，由 Impeller 回退 GLES
- ✅ 模糊 Pass 限制在 1/4 分辨率；玻璃面板限制在标题栏/TabBar/卡片等局部区域
