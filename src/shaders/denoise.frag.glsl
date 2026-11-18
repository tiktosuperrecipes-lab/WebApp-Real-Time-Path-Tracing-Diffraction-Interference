precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 vUv;
out vec4 fragColor;

uniform sampler2D uColorTex;
uniform sampler2D uGBufferTex;
uniform ivec2 uTexSize;
uniform int uPassIndex;
uniform int uStepSize;
uniform int uSampleCount;
uniform float uNoiseScale;

const float KERNEL[3] = float[3](0.25, 0.5, 0.25);

float getLuminance(vec3 c) {
  return max(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0);
}

vec3 toPerceptual(vec3 c) {
  return sqrt(max(c, vec3(0.0)));
}

void main() {
  ivec2 pix = ivec2(gl_FragCoord.xy);
  vec4 centerSample = texelFetch(uColorTex, pix, 0);
  vec4 centerGBuf = texelFetch(uGBufferTex, pix, 0);

  vec3 centerColor = centerSample.rgb;
  float centerDepth = centerGBuf.w;
  float normalLen = length(centerGBuf.xyz);

  // Céu ou superfícies especulares/refrativas/CD (normalLen ~ 0.5) passam 100% intactas
  if (centerDepth < 0.0 || normalLen < 0.75) {
    fragColor = vec4(centerColor, 0.0);
    return;
  }

  vec3 centerNormal = centerGBuf.xyz / normalLen;
  vec3 centerPercep = toPerceptual(centerColor);
  float centerLum = getLuminance(centerColor);

  float centerVar = (uPassIndex == 0)
    ? max(0.0, centerSample.a - centerLum * centerLum) / float(max(uSampleCount, 1))
    : centerSample.a;

  // Desvio perceptual via regra delta: sigma(sqrt(L)) ~= sigma(L) / (2 * sqrt(L))
  float sigmaPercep = sqrt(max(centerVar, 0.0)) / (2.0 * sqrt(max(centerLum, 0.02)));
  float sppFade = 1.0 / (1.0 + float(max(uSampleCount, 1)) * 0.03);
  float baseSigma = (0.085 * uNoiseScale) / sqrt(float(max(uSampleCount, 1)));
  float phiColor = max(max(1.25 * uNoiseScale * sigmaPercep, baseSigma) * sppFade, 0.008);
  float phiDepth = max(0.018 * centerDepth, 0.005);

  vec3 sumColor = vec3(0.0);
  float sumVar = 0.0;
  float sumWeight = 0.0;

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      ivec2 samplePix = clamp(pix + ivec2(dx, dy) * uStepSize, ivec2(0), uTexSize - 1);
      vec4 sGBuf = texelFetch(uGBufferTex, samplePix, 0);
      float sNormalLen = length(sGBuf.xyz);
      if (sGBuf.w < 0.0 || sNormalLen < 0.75) continue;

      vec4 sSample = texelFetch(uColorTex, samplePix, 0);
      vec3 sColor = sSample.rgb;
      vec3 sPercep = toPerceptual(sColor);
      float sLum = getLuminance(sColor);

      float sVar = (uPassIndex == 0)
        ? max(0.0, sSample.a - sLum * sLum) / float(max(uSampleCount, 1))
        : sSample.a;

      vec3 sNormal = sGBuf.xyz / sNormalLen;
      float wKernel = KERNEL[dx + 1] * KERNEL[dy + 1];
      float wNormal = pow(max(0.0, dot(centerNormal, sNormal)), 64.0);
      float wDepth = exp(-abs(centerDepth - sGBuf.w) / phiDepth);
      float wColor = exp(-length(centerPercep - sPercep) / phiColor);

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