precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 vUv;
out vec4 fragColor;

uniform sampler2D uColorTex;
uniform sampler2D uGBufferTex;
uniform sampler2D uAlbedoTex;
uniform mat4 uCamMatrix;
uniform float uTanHalfFov;
uniform float uAspect;
uniform ivec2 uTexSize;
uniform int uPassIndex;
uniform int uStepSize;
uniform int uSampleCount;
uniform float uNoiseScale;

const float KERNEL[3] = float[3](0.25, 0.5, 0.25);

float getLuminance(vec3 c) {
  return max(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0);
}

vec3 getRayDir(ivec2 pix, mat3 camRot) {
  vec2 ndc = ((vec2(pix) + 0.5) / vec2(uTexSize)) * 2.0 - 1.0;
  return normalize(camRot * normalize(vec3(ndc.x * uAspect * uTanHalfFov, ndc.y * uTanHalfFov, -1.0)));
}

void main() {
  ivec2 pix = ivec2(gl_FragCoord.xy);
  vec4 centerSample = texelFetch(uColorTex, pix, 0);
  vec4 centerGBuf = texelFetch(uGBufferTex, pix, 0);
  vec4 centerAlbedoBuf = texelFetch(uAlbedoTex, pix, 0);

  float centerDepth = centerGBuf.w;
  if (centerDepth < 0.0) {
    fragColor = vec4(centerSample.rgb, 0.0);
    return;
  }

  vec3 centerNormal = centerGBuf.xyz;
  bool isDiffuse = centerAlbedoBuf.a > 0.5;
  vec3 safeAlbedo = isDiffuse ? max(centerAlbedoBuf.rgb, vec3(0.04)) : vec3(1.0);
  mat3 camRot = mat3(uCamMatrix);
  vec3 centerRelPos = getRayDir(pix, camRot) * centerDepth;

  // ---------------- Passe 0: Desmodulacao + Firefly Rejection + Variancia 3x3 ----------------
  if (uPassIndex == 0) {
    vec3 centerIrr = centerSample.rgb / safeAlbedo;
    float centerIrrLum = getLuminance(centerIrr);

    float sumLum = 0.0;
    float sumLum2 = 0.0;
    float nCount = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        ivec2 sPix = clamp(pix + ivec2(dx, dy), ivec2(0), uTexSize - 1);
        vec4 sGBuf = texelFetch(uGBufferTex, sPix, 0);
        if (sGBuf.w < 0.0) continue;

        vec4 sAlbBuf = texelFetch(uAlbedoTex, sPix, 0);
        bool sDiff = sAlbBuf.a > 0.5;
        if (sDiff != isDiffuse) continue;
        if (dot(centerNormal, sGBuf.xyz) < 0.75) continue;

        vec3 sRelPos = getRayDir(sPix, camRot) * sGBuf.w;
        float planeDist = abs(dot(centerNormal, sRelPos - centerRelPos));
        if (planeDist > max(0.03 * centerDepth, 0.015)) continue;

        vec3 sSafeAlb = sDiff ? max(sAlbBuf.rgb, vec3(0.04)) : vec3(1.0);
        vec3 sIrr = texelFetch(uColorTex, sPix, 0).rgb / sSafeAlb;
        float sLum = getLuminance(sIrr);

        sumLum += sLum;
        sumLum2 += sLum * sLum;
        nCount += 1.0;
      }
    }

    float spatialVar = 0.0;
    if (nCount > 0.5) {
      float meanLum = sumLum / nCount;
      spatialVar = max(0.0, (sumLum2 / nCount) - meanLum * meanLum);
      float spikeCeiling = meanLum + 3.0 * sqrt(spatialVar) + 0.15 * meanLum + 0.06;
      if (centerIrrLum > spikeCeiling && centerIrrLum > 1e-5) {
        centerIrr *= (spikeCeiling / centerIrrLum);
      }
    }

    if (!isDiffuse) {
      fragColor = vec4(centerIrr, 0.0);
      return;
    }

    float rawLum = getLuminance(centerSample.rgb);
    float albLum = max(getLuminance(safeAlbedo), 0.04);
    float temporalVar = max(0.0, centerSample.a - rawLum * rawLum) / (float(max(uSampleCount, 1)) * albLum * albLum);
    float spatialWeight = 1.0 / (1.0 + float(max(uSampleCount, 1)) * 0.25);
    float outVar = mix(temporalVar, max(temporalVar, spatialVar * 0.75), spatialWeight);

    fragColor = vec4(centerIrr, outVar);
    return;
  }

  // Vidro, metal e CD passam intactos nos passes espaciais (so tiveram anti-firefly no passe 0)
  if (!isDiffuse) {
    fragColor = vec4(centerSample.rgb, 0.0);
    return;
  }

  // ---------------- Passes 1..3: A-Trous guiado por Plano 3D + Variancia ----------------
  vec3 centerIrr = centerSample.rgb;
  vec3 centerPercep = sqrt(max(centerIrr, vec3(0.0)));
  float centerIrrLum = getLuminance(centerIrr);

  // Filtra levemente a variancia em 3x3 para evitar manchas no phiColor
  float varSum = 0.0;
  float varW = 0.0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      ivec2 vPix = clamp(pix + ivec2(dx, dy), ivec2(0), uTexSize - 1);
      if (texelFetch(uGBufferTex, vPix, 0).w < 0.0) continue;
      if (texelFetch(uAlbedoTex, vPix, 0).a <= 0.5) continue;
      float wk = KERNEL[dx + 1] * KERNEL[dy + 1];
      varSum += texelFetch(uColorTex, vPix, 0).a * wk;
      varW += wk;
    }
  }
  float filteredVar = (varW > 1e-5) ? (varSum / varW) : centerSample.a;

  // Regra delta: desvio em sqrt(L) ~= sigma(L) / (2 * sqrt(L))
  float sigmaPercep = sqrt(max(filteredVar, 0.0)) / (2.0 * sqrt(max(centerIrrLum, 0.03)));
  float floorPhi = (0.04 * uNoiseScale) / sqrt(float(max(uSampleCount, 1)));
  float phiColor = max(1.8 * uNoiseScale * sigmaPercep, floorPhi) + 0.005;
  float phiPlane = max(0.015 * centerDepth, 0.006);

  vec3 sumIrr = vec3(0.0);
  float sumVar = 0.0;
  float sumWeight = 0.0;

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      ivec2 sPix = clamp(pix + ivec2(dx, dy) * uStepSize, ivec2(0), uTexSize - 1);
      vec4 sGBuf = texelFetch(uGBufferTex, sPix, 0);
      if (sGBuf.w < 0.0) continue;
      if (texelFetch(uAlbedoTex, sPix, 0).a <= 0.5) continue;

      vec4 sSample = texelFetch(uColorTex, sPix, 0);
      vec3 sIrr = sSample.rgb;
      vec3 sPercep = sqrt(max(sIrr, vec3(0.0)));

      vec3 sRelPos = getRayDir(sPix, camRot) * sGBuf.w;
      float planeDist = abs(dot(centerNormal, sRelPos - centerRelPos));

      float wKernel = KERNEL[dx + 1] * KERNEL[dy + 1];
      float wNormal = pow(max(0.0, dot(centerNormal, sGBuf.xyz)), 64.0);
      float wPlane = exp(-planeDist / phiPlane);
      float wColor = exp(-length(centerPercep - sPercep) / phiColor);

      float w = wKernel * wNormal * wPlane * wColor;

      sumIrr += sIrr * w;
      sumVar += sSample.a * (w * w);
      sumWeight += w;
    }
  }

  vec3 outIrr = (sumWeight > 1e-6) ? (sumIrr / sumWeight) : centerIrr;
  float outVar = (sumWeight > 1e-6) ? (sumVar / (sumWeight * sumWeight)) : centerSample.a;

  // Passe final (3): remodula pelo albedo nitido original
  if (uPassIndex == 3) {
    fragColor = vec4(outIrr * safeAlbedo, 1.0);
  } else {
    fragColor = vec4(outIrr, outVar);
  }
}