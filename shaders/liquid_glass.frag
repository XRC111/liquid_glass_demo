#version 320 es
// ============================================================================
// 液态玻璃核心片元着色器 (Liquid Glass fragment shader)
//
// 特性:
//   1. SDF 圆角矩形定义玻璃形状与抗锯齿边缘
//   2. 高度场 + 中心差分梯度求表面法线
//   3. 高度场折射: 边缘弯曲区像素偏移, 中心平坦区保持原样
//   4. RGB 三通道分离色散 (chromatic aberration)
//   5. Fresnel 边缘高光 + 上缘亮线
//   6. 触摸位置动态光照 (Blinn-Phong 高光跟随手指)
//   7. Y 轴翻转处理: OpenGL ES 后端纹理与 Vulkan 方向相反
//
// 兼容性:
//   - Impeller Vulkan 后端 (Android API 29+): 编译为 SPIR-V
//   - Impeller OpenGL ES 后端 (Android API 24-28): 编译为 GLSL ES
//   - 两套目标由 Flutter 工具链在构建期从本文件自动生成
//
// uniform 布局注意: Impeller 要求 sampler 必须声明在其它 uniform 之前,
// 且 sampler 不占用 setFloat 的 float 索引 (setImageSampler 单独编号)。
// ============================================================================
#include <flutter/runtime_effect.glsl>

// sampler 0: 玻璃后方的背景纹理
//   - full / medium 质量: 经过 1/4 分辨率高斯模糊的背景
//   - minimal 质量: 原始清晰背景 (跳过模糊 Pass)
uniform sampler2D uBackground;

uniform vec2 uSize;          // f0, f1   玻璃尺寸 (逻辑像素)
uniform vec2 uBgSize;        // f2, f3   背景对应的逻辑尺寸
uniform vec2 uBgOffset;      // f4, f5   玻璃左上角在背景中的位置 (逻辑像素)
uniform float uCornerRadius; // f6       圆角半径 (逻辑像素)
uniform float uRefraction;   // f7       折射强度
uniform float uDispersion;   // f8       色散强度 (0-1, minimal 质量强制为 0)
uniform float uFresnel;      // f9       Fresnel 边缘高光强度
uniform vec2 uTouch;         // f10, f11 触摸点 (玻璃局部坐标, 无触摸时为 -1e6)
uniform float uTime;         // f12      时间 (秒, 驱动液态微波纹)
uniform float uOpacity;      // f13      整体不透明度 (minimal 半透明降级用)

out vec4 fragColor;

// ----------------------------------------------------------------------------
// SDF: 圆角矩形有向距离场 (负值在内部, 正值在外部)
// ----------------------------------------------------------------------------
float sdRoundRect(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + vec2(radius);
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

// ----------------------------------------------------------------------------
// 高度场: 玻璃横截面轮廓 (边缘弯曲, 中心平坦的半球冠)
// ----------------------------------------------------------------------------
float heightField(float sd, float thickness) {
  float t = clamp(-sd / max(thickness, 1e-3), 0.0, 1.0);
  return sqrt(max(0.0, 2.0 * t - t * t));
}

// ----------------------------------------------------------------------------
// Y 轴翻转: OpenGL ES 后端纹理 Y 轴与 Vulkan 相反, 采样前需要翻转。
// 新版引擎在 top-down 模式下会定义 IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED,
// 此时跳过翻转以保持两个后端行为一致。
// ----------------------------------------------------------------------------
vec2 flipIfGles(vec2 uv) {
#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
  return vec2(uv.x, 1.0 - uv.y);
#else
  return uv;
#endif
}

// 采样背景: 输入背景逻辑坐标, 输出过滤后的颜色
vec4 sampleBg(vec2 logicalPos) {
  vec2 uv = clamp(logicalPos / uBgSize, vec2(0.0), vec2(1.0));
  return texture(uBackground, flipIfGles(uv));
}

void main() {
  vec2 p = FlutterFragCoord().xy; // 玻璃局部坐标 (左上原点)
  vec2 center = uSize * 0.5;
  vec2 halfSize = uSize * 0.5 - vec2(1.0);
  // 玻璃厚度轮廓宽度 = 弯曲区宽度, 与圆角关联
  float thickness = clamp(uCornerRadius * 1.6, 8.0, min(uSize.x, uSize.y) * 0.5);

  // ---- SDF 与高度场 ----
  float sd = sdRoundRect(p - center, halfSize, uCornerRadius);
  float e = 1.0;
  float hL = heightField(sdRoundRect(p - center - vec2(e, 0.0), halfSize, uCornerRadius), thickness);
  float hR = heightField(sdRoundRect(p - center + vec2(e, 0.0), halfSize, uCornerRadius), thickness);
  float hD = heightField(sdRoundRect(p - center - vec2(0.0, e), halfSize, uCornerRadius), thickness);
  float hU = heightField(sdRoundRect(p - center + vec2(0.0, e), halfSize, uCornerRadius), thickness);
  float hC = heightField(sd, thickness);

  // ---- 中心差分梯度 -> 表面法线 ----
  vec2 grad = vec2(hR - hL, hU - hD) / (2.0 * e);
  vec3 normal = normalize(vec3(-grad, 1.0));

  // ---- 液态微波纹 (时间驱动, 让内部产生轻微流动折射) ----
  float tt = uTime;
  vec2 ripple = vec2(
    sin(p.x * 0.020 + tt * 1.35) * cos(p.y * 0.017 - tt * 0.95),
    sin(p.y * 0.023 - tt * 1.10) * cos(p.x * 0.015 + tt * 0.80)
  );

  // ---- 高度场折射偏移: 边缘弯曲区强, 中心平坦区几乎为零 ----
  vec2 bend = normal.xy * uRefraction * thickness * 0.9
            + ripple * uRefraction * 1.6;

  // ---- RGB 三通道分离色散 ----
  vec2 bendR = bend * (1.0 + uDispersion * 0.90);
  vec2 bendG = bend;
  vec2 bendB = bend * (1.0 - uDispersion * 0.90);

  vec2 bgPos = uBgOffset + p;
  vec3 refracted = vec3(
    sampleBg(bgPos + bendR).r,
    sampleBg(bgPos + bendG).g,
    sampleBg(bgPos + bendB).b
  );

  vec3 color = refracted;
  // 玻璃白雾底色, 提供基础"材质感"
  color = mix(color, vec3(1.0), 0.05);

  // ---- Fresnel 边缘高光 ----
  float fresnel = pow(1.0 - clamp(normal.z, 0.0, 1.0), 3.0);
  float rim = 1.0 - smoothstep(0.0, thickness * 0.45, -sd);
  color += vec3(1.0) * fresnel * rim * uFresnel * 0.55;
  color += vec3(1.0) * fresnel * uFresnel * 0.10;

  // 上缘亮线 (光源来自上方) / 下缘轻微暗影, 增强立体感
  float upLight = clamp(-normal.y, 0.0, 1.0);
  float dnLight = clamp(normal.y, 0.0, 1.0);
  color += vec3(1.0) * rim * upLight * uFresnel * 0.85;
  color = mix(color, color * 0.82, rim * dnLight * 0.5);

  // ---- 触摸位置动态光照 (Blinn-Phong) ----
  vec2 toTouch = uTouch - p;
  float dist2 = dot(toTouch, toTouch);
  float atten = exp(-dist2 / 16200.0); // 高斯衰减半径 ~90px, 无触摸时自然为 0
  vec3 L = normalize(vec3(toTouch, 70.0));
  float diff = max(dot(normal, L), 0.0);
  vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
  float spec = pow(max(dot(normal, hv), 0.0), 64.0);
  color += (spec * 0.85 + diff * 0.08) * atten;

  // ---- 抗锯齿 alpha ----
  float alpha = 1.0 - smoothstep(0.0, 1.5, sd);
  fragColor = vec4(color, alpha * uOpacity);
}
