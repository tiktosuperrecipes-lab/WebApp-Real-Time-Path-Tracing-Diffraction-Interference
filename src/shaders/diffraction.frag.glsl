precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 vUv;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGBuffer;
layout(location = 2) out vec4 outAlbedo;

uniform sampler2D uAccumTexture;
uniform sampler2D uWorldPhotonTex;
uniform vec2 uResolution;
uniform int uSampleCount;
uniform int uSamplesPerFrame;
uniform int uLaserMode;
uniform int uSlit1Blocked;

uniform vec3 uCamPos;
uniform mat4 uCamMatrix;
uniform float uTanHalfFov;
uniform float uAspect;

//#include <common>
//#include <rng>
//#include <spectrum>
//#include <sampling>
//#include <intersections>
//#include <lenses>
//#include <diffractionScene>
//#include <diffractionOptics>

const int MIN_BOUNCES_RR = 2;
const int MAX_BOUNCES = 8;

vec3 tracePath(
  vec3 ro,
  vec3 rd,
  float glassLambda,
  float laserLambda,
  inout uint rng,
  out vec3 primaryNormal,
  out float primaryDepth,
  out vec3 primaryAlbedo,
  out float primaryIsDiffuse
) {
  vec3 radianceRGB = vec3(0.0);
  vec3 throughputRGB = vec3(1.0);
  bool lastBounceSpecular = true;
  bool lastBounceDiffractive = false;
  bool usedSpectral = false;

  primaryNormal = vec3(0.0);
  primaryDepth = -1.0;
  primaryAlbedo = vec3(1.0);
  primaryIsDiffuse = 0.0;

  vec3 laserSpectrumRGB = max(wavelengthToLinearRGB(laserLambda), vec3(0.0));

  for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {
    HitInfo hit;
    if (!traceScene(ro, rd, T_MAX, hit)) {
      radianceRGB += throughputRGB * vec3(0.010);
      break;
    }

    if (bounce == 0) {
      primaryNormal = hit.normal;
      primaryDepth = hit.t;
      primaryIsDiffuse = (hit.matType == MAT_DIFFUSE) ? 1.0 : 0.0;
      primaryAlbedo = (hit.matType == MAT_DIFFUSE) ? hit.albedo : vec3(1.0);
    }

    if (hit.matType == MAT_LIGHT) {
      if (lastBounceSpecular) radianceRGB += throughputRGB * hit.emission;
      break;
    }

    if (hit.matType == MAT_LASER_LENS) {
      if (lastBounceSpecular || lastBounceDiffractive) {
        radianceRGB += throughputRGB * laserSpectrumRGB * (hit.emission * 0.35);
      }
      break;
    }

    if (hit.matType == MAT_DIFFUSE) {
      radianceRGB += throughputRGB * sampleOverheadLightRGB(hit, rng);

      bool skipDirectScreenLaser = lastBounceDiffractive && (hit.surfaceId == SURF_SCREEN);
      if (!skipDirectScreenLaser && hit.surfaceId != SURF_NONE) {
        radianceRGB += throughputRGB * sampleWorldPhotonMap(hit);
      }

      ro = hit.pos + hit.normal * EPS;
      rd = sampleCosineHemisphere(hit.normal, rng);
      throughputRGB *= hit.albedo;
      lastBounceSpecular = false;
      lastBounceDiffractive = false;
    } else if (hit.matType == MAT_GRATING) {
      radianceRGB += throughputRGB * sampleGratingDiffractionRGB(hit, -rd, laserLambda, rng);

      vec3 V = -rd;
      if (rand(rng) < 0.80) {
        float alpha = max(hit.roughness * hit.roughness, 0.003);
        float alpha2 = alpha * alpha;
        vec3 H = sampleGGXHalfVector(hit.normal, alpha, rng);
        vec3 L = reflect(-V, H);

        float NoL = dot(hit.normal, L);
        float NoV = dot(hit.normal, V);
        float NoH = dot(hit.normal, H);
        float VoH = dot(V, H);
        if (NoL <= 0.0 || NoV <= 1e-5 || NoH <= 1e-5 || VoH <= 0.0) break;

        float F = fresnelSchlickScalar(VoH, 0.72);
        float G = smithG1(NoV, alpha2) * smithG1(NoL, alpha2);
        float weight = F * ((G * VoH) / (NoH * NoV));

        ro = hit.pos + hit.normal * EPS;
        rd = normalize(L);
        throughputRGB *= clamp(weight, 0.0, 1.0);
        lastBounceSpecular = true;
        lastBounceDiffractive = false;
      } else {
        vec2 d = hit.pos.xz - DISC_CENTER.xz;
        float lenD = length(d);
        if (lenD < 1e-5) break;

        vec3 R = vec3(d.x / lenD, 0.0, d.y / lenD);
        vec3 T = vec3(-R.z, 0.0, R.x);

        int signM = (rand(rng) < 0.5) ? -1 : 1;
        int magM = (rand(rng) < 0.74) ? 1 : 2;
        float uTarget = float(signM * magM) * (glassLambda / GRATING_PITCH_NM);

        float rG = sqrt(-2.0 * log(max(rand(rng), 1e-6)));
        float aG = 2.0 * PI * rand(rng);
        float du = 0.014 * rG * cos(aG);
        float dv = 0.085 * rG * sin(aG);

        float L_R = (uTarget + du) - dot(R, V);
        float L_T = dv - dot(T, V);
        float horiz2 = L_R * L_R + L_T * L_T;
        if (horiz2 >= 0.995) break;

        vec3 L = normalize(R * L_R + T * L_T + vec3(0.0, sqrt(1.0 - horiz2), 0.0));
        if (!usedSpectral) {
          throughputRGB *= max(wavelengthToLinearRGB(glassLambda), vec3(0.0));
          usedSpectral = true;
        }

        ro = hit.pos + hit.normal * EPS;
        rd = L;
        throughputRGB *= (magM == 1) ? 0.55 : 0.40;
        lastBounceSpecular = false;
        lastBounceDiffractive = true;
      }
    } else if (hit.matType == MAT_METAL) {
      float alpha = max(hit.roughness * hit.roughness, 0.002);
      float alpha2 = alpha * alpha;
      vec3 V = -rd;
      vec3 H = sampleGGXHalfVector(hit.normal, alpha, rng);
      vec3 L = reflect(-V, H);

      float NoL = dot(hit.normal, L);
      float NoV = dot(hit.normal, V);
      float NoH = dot(hit.normal, H);
      float VoH = dot(V, H);
      if (NoL <= 0.0 || NoV <= 1e-5 || NoH <= 1e-5 || VoH <= 0.0) break;

      vec3 F = fresnelSchlickRGB(VoH, hit.albedo);
      float G = smithG1(NoV, alpha2) * smithG1(NoL, alpha2);
      vec3 weight = F * ((G * VoH) / (NoH * NoV));

      ro = hit.pos + hit.normal * EPS;
      rd = normalize(L);
      throughputRGB *= clamp(weight, vec3(0.0), vec3(1.0));
      lastBounceSpecular = true;
      lastBounceDiffractive = false;
    } else if (hit.matType == MAT_GLASS) {
      if (!usedSpectral) {
        throughputRGB *= max(wavelengthToLinearRGB(glassLambda), vec3(0.0));
        usedSpectral = true;
      }

      float lamUm = glassLambda * 0.001;
      float ior = 1.49 + 0.015 / (lamUm * lamUm);

      float eta = hit.frontFace ? (1.0 / ior) : ior;
      float cosTheta = min(dot(-rd, hit.normal), 1.0);
      float sin2Theta = max(0.0, 1.0 - cosTheta * cosTheta);
      bool cannotRefract = (eta * eta * sin2Theta) > 1.0;

      float r0 = (1.0 - eta) / (1.0 + eta);
      r0 = r0 * r0;
      float fresnel = r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);

      vec3 nextDir = (cannotRefract || rand(rng) < fresnel) ? reflect(rd, hit.normal) : refract(rd, hit.normal, eta);
      vec3 offsetNormal = (cannotRefract || dot(nextDir, hit.normal) > 0.0) ? hit.normal : -hit.normal;

      ro = hit.pos + offsetNormal * EPS;
      rd = normalize(nextDir);
      throughputRGB *= 0.98;
      lastBounceSpecular = true;
      lastBounceDiffractive = false;
    }

    float maxT = max(throughputRGB.r, max(throughputRGB.g, throughputRGB.b));
    if (maxT < 0.001) break;

    if (bounce >= MIN_BOUNCES_RR) {
      float pSurvive = clamp(maxT, 0.05, 0.95);
      if (rand(rng) > pSurvive) break;
      throughputRGB /= pSurvive;
    }
  }

  return radianceRGB;
}

void main() {
  vec3 batchColorSum = vec3(0.0);
  float batchLum2Sum = 0.0;
  vec3 primaryNormal = vec3(0.0);
  float primaryDepth = -1.0;
  vec3 primaryAlbedo = vec3(1.0);
  float primaryIsDiffuse = 0.0;
  mat3 camRot = mat3(uCamMatrix);

  uint pixRng = uint(gl_FragCoord.x) * 1973u ^ uint(gl_FragCoord.y) * 9277u ^ 0x9E3779B9u;
  float pixelLambdaBase = rand(pixRng);

  for (int s = 0; s < uSamplesPerFrame; s++) {
    uint rng = uint(gl_FragCoord.x);
    rng = pcgHash(rng) ^ uint(gl_FragCoord.y);
    rng = pcgHash(rng) ^ uint(uSampleCount + s);
    rng = pcgHash(rng);

    vec2 pixelCoord = floor(gl_FragCoord.xy) + vec2(rand(rng), rand(rng));
    vec2 ndc = (pixelCoord / uResolution) * 2.0 - 1.0;
    vec3 rayDir = normalize(camRot * normalize(vec3(ndc.x * uAspect * uTanHalfFov, ndc.y * uTanHalfFov, -1.0)));

    float uLambda = fract(pixelLambdaBase + float(uSampleCount + s) * 0.61803398875);
    float glassLambda = mix(380.0, 720.0, uLambda);
    float laserLambda = sampleLaserWavelength(glassLambda, rng);

    vec3 n0;
    float d0;
    vec3 a0;
    float isDiff0;
    vec3 sampleColor = tracePath(uCamPos, rayDir, glassLambda, laserLambda, rng, n0, d0, a0, isDiff0);
    if (any(isnan(sampleColor)) || any(isinf(sampleColor))) sampleColor = vec3(0.0);

    batchColorSum += sampleColor;
    float lum = max(dot(sampleColor, vec3(0.2126, 0.7152, 0.0722)), 0.0);
    batchLum2Sum += lum * lum;

    if (s == 0) {
      primaryNormal = n0;
      primaryDepth = d0;
      primaryAlbedo = a0;
      primaryIsDiffuse = isDiff0;
    }
  }

  float invBatch = 1.0 / float(uSamplesPerFrame);
  vec3 batchColor = batchColorSum * invBatch;
  float batchLum2 = batchLum2Sum * invBatch;

  if (uSampleCount == 0) {
    outColor = vec4(batchColor, batchLum2);
  } else {
    vec4 prev = texelFetch(uAccumTexture, ivec2(gl_FragCoord.xy), 0);
    float totalSamples = float(uSampleCount + uSamplesPerFrame);
    float weight = float(uSamplesPerFrame) / totalSamples;
    outColor = vec4(mix(prev.rgb, batchColor, weight), mix(prev.a, batchLum2, weight));
  }

  outGBuffer = vec4(primaryNormal, primaryDepth);
  outAlbedo = vec4(primaryAlbedo, primaryIsDiffuse);
}