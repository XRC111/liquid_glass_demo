#version 320 es
// ============================================================================
// 可分离高斯模糊 - 水平 Pass (Separable Gaussian blur, horizontal pass)
//
// 在 1/4 分辨率的离屏缓冲上执行, 与垂直 Pass 配合完成两次一维卷积,
// 计算量相对全分辨率 2D 卷积减少 ~94%。
// Android API 24-28 上由 Impeller OpenGL ES 后端执行, 同样适用 Y 轴翻转处理。
// ============================================================================
#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture; // 输入纹理 (下采样后的背景)
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
  // 水平方向 11-tap 高斯卷积
  vec2 texel = vec2(1.0, 0.0) / uSize;
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
