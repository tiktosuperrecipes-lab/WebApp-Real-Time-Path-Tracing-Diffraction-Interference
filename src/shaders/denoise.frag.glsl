precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 vUv;
out vec4 fragColor;

uniform sampler2D uColorTex;
uniform sampler2D uExtraTex;
uniform sampler2D uGBufferTex;
uniform ivec2 uTexSize;
uniform int uPassIndex;
uniform int uStepSize;
uniform int uSampleCount;
uniform int uHasExtraTex;
uniform float uNoiseScale;

const float KERNEL[3] = float[3](0.25, 0.5, 0.25);

float getLuminance(vec3 c) {
  return max(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0);
}

void main() {
  ivec2 pix = ivec2(gl_FragCoord.xy);
  vec4 centerSample = texelFetch(uColorTex, pix, 0);
  vec4 centerGBuf = texelFetch(uGBufferTex, pix, 0);

  vec3 centerExtra = (uPassIndex == 0 && uHasExtraTex == 1)
    ? texelFetch(uExtraTex, pix, 0).rgb
    : vec3(0.0);
  vec3 centerColor = centerSample.rgb + centerExtra;
  float centerDepth = centerGBuf.w;

  if (centerDepth < 0.0) {
    fragColor = vec4(centerColor, 0.0);
    return;
  }

  vec3 centerNormal = centerGBuf.xyz;
  float centerLum = getLuminance(centerColor);

  float centerVar = (uPassIndex == 0)
    ? max(0.0, centerSample.a - centerLum * centerLum) / float(max(uSampleCount, 1))
    : centerSample.a;

  float baseSigma = (0.45 * uNoiseScale) / sqrt(float(max(uSampleCount, 1)));
  float phiColor = max(1.8 * uNoiseScale * sqrt(max(centerVar, 0.0)), baseSigma) + 0.01;
  float phiDepth = max(0.06 * centerDepth, 0.02);

  vec3 sumColor = vec3(0.0);
  float sumVar = 0.0;
  float sumWeight = 0.0;

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      ivec2 samplePix = clamp(pix + ivec2(dx, dy) * uStepSize, ivec2(0), uTexSize - 1);
      vec4 sGBuf = texelFetch(uGBufferTex, samplePix, 0);
      if (sGBuf.w < 0.0) continue;

      vec4 sSample = texelFetch(uColorTex, samplePix, 0);
      vec3 sExtra = (uPassIndex == 0 && uHasExtraTex == 1)
        ? texelFetch(uExtraTex, samplePix, 0).rgb
        : vec3(0.0);
      vec3 sColor = sSample.rgb + sExtra;
      float sLum = getLuminance(sColor);

      float sVar = (uPassIndex == 0)
        ? max(0.0, sSample.a - sLum * sLum) / float(max(uSampleCount, 1))
        : sSample.a;

      float wKernel = KERNEL[dx + 1] * KERNEL[dy + 1];
      float wNormal = pow(max(0.0, dot(centerNormal, sGBuf.xyz)), 32.0);
      float wDepth = exp(-abs(centerDepth - sGBuf.w) / phiDepth);
      float wColor = exp(-abs(centerLum - sLum) / phiColor);

      float w = wKernel * wNormal * wDepth * wColor;

      sumColor += sColor * w;
      sumVar += sVar * (w * w);
      sumWeight += w;
    }
  }

  if (sumWeight > 1e-6) {
    float invW = 1.0 / sumWeight;
    fragColor = vec4(sumColor * invW, sumVar * invW * invW);
  } else {
    fragColor = vec4(centerColor, centerVar);
  }
}