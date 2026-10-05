#version 320 es
// ============================================================================
// 可分离高斯模糊 - 垂直 Pass (Separable Gaussian blur, vertical pass)
//
// 输入为水平 Pass 的输出, 两个 Pass 均在 1/4 分辨率缓冲上执行。
// ============================================================================
#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture; // 输入纹理 (水平 Pass 的输出)
uniform vec2 uSize;         // f0, f1  模糊缓冲尺寸 (物理像素)
uniform float uRadius;      // f2      模糊半径 (缓冲像素, 0 表示仅中心采样)

out vec4 fragColor;

// Y 轴翻转: 与 liquid_glass.frag 保持完全一致的纹理方向语义
vec2 flipIfGles(vec2 uv) {
#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
  return vec2(uv.x, 1.0 - uv.y);
#else
  return uv;
#endif
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  // 垂直方向 11-tap 高斯卷积
  vec2 texel = vec2(0.0, 1.0) / uSize;
  vec4 sum = vec4(0.0);
  float wsum = 0.0;
  for (int i = -5; i <= 5; i++) {
    float fi = float(i);
    float w = exp(-(fi * fi) / (2.0 * uRadius * uRadius + 1e-6));
    vec2 suv = clamp(uv + texel * fi, vec2(0.0), vec2(1.0));
    sum += texture(uTexture, flipIfGles(suv)) * w;
    wsum += w;
  }
  fragColor = sum / wsum;
}
