precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 vUv;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGBuffer;

uniform sampler2D uAccumTexture;
uniform vec2 uResolution;
uniform int uSampleCount;
uniform int uSamplesPerFrame;

uniform vec3 uCamPos;
uniform mat4 uCamMatrix;
uniform float uTanHalfFov;
uniform float uAspect;

//#include <common>
//#include <rng>
//#include <sampling>
//#include <intersections>

const int MIN_BOUNCES_RR = 2;
const int MAX_BOUNCES = 8;

const int MAT_DIFFUSE = 0;
const int MAT_METAL = 1;
const int MAT_GLASS = 2;
const int MAT_LIGHT = 3;

const vec3 LIGHT_MIN = vec3(-0.35, 0.999, -0.35);
const vec3 LIGHT_MAX = vec3(0.35, 0.999, 0.35);
const vec3 LIGHT_NORMAL = vec3(0.0, -1.0, 0.0);
const vec3 LIGHT_EMISSION = vec3(15.0, 14.0, 12.0);
const float LIGHT_AREA = 0.7 * 0.7;

const vec3 SPHERE_DIFFUSE_POS = vec3(-0.48, -0.68, -0.35);
const float SPHERE_DIFFUSE_R = 0.32;
const vec3 SPHERE_METAL_POS = vec3(0.45, -0.64, -0.25);
const float SPHERE_METAL_R = 0.36;
const vec3 SPHERE_GLASS_POS = vec3(-0.05, -0.70, 0.38);
const float SPHERE_GLASS_R = 0.30;

struct HitInfo {
  float t;
  vec3 pos;
  vec3 normal;
  bool frontFace;
  vec3 albedo;
  vec3 emission;
  float roughness;
  float ior;
  int matType;
};

bool traceShadow(vec3 ro, vec3 rd, float maxDist) {
  if (intersectSphereAny(ro, rd, SPHERE_DIFFUSE_POS, SPHERE_DIFFUSE_R, maxDist)) return true;
  if (intersectSphereAny(ro, rd, SPHERE_METAL_POS, SPHERE_METAL_R, maxDist)) return true;
  if (intersectSphereAny(ro, rd, SPHERE_GLASS_POS, SPHERE_GLASS_R, maxDist)) return true;
  return false;
}

void setHitSurface(
  inout HitInfo hit,
  float t,
  vec3 ro,
  vec3 rd,
  vec3 outwardNormal,
  vec3 albedo,
  vec3 emission,
  float roughness,
  float ior,
  int matType
) {
  hit.t = t;
  hit.pos = ro + rd * t;
  hit.frontFace = dot(rd, outwardNormal) < 0.0;
  hit.normal = hit.frontFace ? outwardNormal : -outwardNormal;
  hit.albedo = albedo;
  hit.emission = emission;
  hit.roughness = roughness;
  hit.ior = ior;
  hit.matType = matType;
}

bool traceScene(vec3 ro, vec3 rd, float maxDist, out HitInfo hit) {
  hit.t = maxDist;
  bool anyHit = false;
  float t;
  vec3 n;

  if (intersectQuadY(ro, rd, 0.999, -1.0, LIGHT_MIN.xz, LIGHT_MAX.xz, hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, LIGHT_NORMAL, vec3(0.0), LIGHT_EMISSION, 0.0, 1.0, MAT_LIGHT);
  }
  if (intersectQuadY(ro, rd, -1.0, 1.0, vec2(-1.0), vec2(1.0), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(0.0, 1.0, 0.0), vec3(0.73), vec3(0.0), 1.0, 1.0, MAT_DIFFUSE);
  }
  if (intersectQuadY(ro, rd, 1.0, -1.0, vec2(-1.0), vec2(1.0), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(0.0, -1.0, 0.0), vec3(0.73), vec3(0.0), 1.0, 1.0, MAT_DIFFUSE);
  }
  if (intersectQuadZ(ro, rd, -1.0, 1.0, vec2(-1.0), vec2(1.0), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(0.0, 0.0, 1.0), vec3(0.73), vec3(0.0), 1.0, 1.0, MAT_DIFFUSE);
  }
  if (intersectQuadX(ro, rd, -1.0, 1.0, vec2(-1.0), vec2(1.0), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(1.0, 0.0, 0.0), vec3(0.65, 0.05, 0.05), vec3(0.0), 1.0, 1.0, MAT_DIFFUSE);
  }
  if (intersectQuadX(ro, rd, 1.0, -1.0, vec2(-1.0), vec2(1.0), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(-1.0, 0.0, 0.0), vec3(0.12, 0.45, 0.15), vec3(0.0), 1.0, 1.0, MAT_DIFFUSE);
  }

  if (intersectSphere(ro, rd, SPHERE_DIFFUSE_POS, SPHERE_DIFFUSE_R, hit.t, t, n)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, n, vec3(0.84, 0.80, 0.74), vec3(0.0), 1.0, 1.0, MAT_DIFFUSE);
  }
  if (intersectSphere(ro, rd, SPHERE_METAL_POS, SPHERE_METAL_R, hit.t, t, n)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, n, vec3(0.95, 0.78, 0.38), vec3(0.0), 0.05, 1.0, MAT_METAL);
  }
  if (intersectSphere(ro, rd, SPHERE_GLASS_POS, SPHERE_GLASS_R, hit.t, t, n)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, n, vec3(0.98, 0.99, 1.0), vec3(0.0), 0.0, 1.5, MAT_GLASS);
  }

  return anyHit;
}

vec3 sampleDirectLight(vec3 hitPos, vec3 hitNormal, vec3 albedo, inout uint rng) {
  vec3 lightPos = vec3(
    mix(LIGHT_MIN.x, LIGHT_MAX.x, rand(rng)),
    LIGHT_MIN.y,
    mix(LIGHT_MIN.z, LIGHT_MAX.z, rand(rng))
  );

  vec3 toLight = lightPos - hitPos;
  float dist2 = dot(toLight, toLight);
  float dist = sqrt(dist2);
  vec3 L = toLight / dist;

  float cosSurf = dot(hitNormal, L);
  float cosLight = dot(LIGHT_NORMAL, -L);
  if (cosSurf <= 0.0 || cosLight <= 0.0) return vec3(0.0);

  if (traceShadow(hitPos + hitNormal * EPS, L, dist - EPS * 2.0)) return vec3(0.0);

  float geom = (cosSurf * cosLight) / dist2;
  return (albedo * INV_PI) * LIGHT_EMISSION * geom * LIGHT_AREA;
}

vec3 tracePath(vec3 ro, vec3 rd, inout uint rng, out vec3 primaryNormal, out float primaryDepth) {
  vec3 radiance = vec3(0.0);
  vec3 throughput = vec3(1.0);
  bool lastBounceSpecular = true;

  primaryNormal = vec3(0.0);
  primaryDepth = -1.0;

  for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {
    HitInfo hit;
    if (!traceScene(ro, rd, T_MAX, hit)) {
      radiance += throughput * vec3(0.015, 0.017, 0.022);
      break;
    }

    if (bounce == 0) {
      primaryNormal = hit.normal * ((hit.matType == MAT_DIFFUSE) ? 1.0 : 0.5);
      primaryDepth = hit.t;
    }

    if (hit.matType == MAT_LIGHT) {
      if (lastBounceSpecular) radiance += throughput * hit.emission;
      break;
    }

    if (hit.matType == MAT_DIFFUSE) {
      radiance += throughput * sampleDirectLight(hit.pos, hit.normal, hit.albedo, rng);
      ro = hit.pos + hit.normal * EPS;
      rd = sampleCosineHemisphere(hit.normal, rng);
      throughput *= hit.albedo;
      lastBounceSpecular = false;
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
      throughput *= clamp(weight, vec3(0.0), vec3(1.0));
      lastBounceSpecular = true;
    } else if (hit.matType == MAT_GLASS) {
      float eta = hit.frontFace ? (1.0 / hit.ior) : hit.ior;
      float cosTheta = min(dot(-rd, hit.normal), 1.0);
      float sin2Theta = max(0.0, 1.0 - cosTheta * cosTheta);
      bool cannotRefract = (eta * eta * sin2Theta) > 1.0;

      float r0 = (1.0 - eta) / (1.0 + eta);
      r0 = r0 * r0;
      float fresnel = r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);

      vec3 nextDir;
      vec3 offsetNormal;
      if (cannotRefract || rand(rng) < fresnel) {
        nextDir = reflect(rd, hit.normal);
        offsetNormal = hit.normal;
      } else {
        nextDir = refract(rd, hit.normal, eta);
        offsetNormal = -hit.normal;
      }

      ro = hit.pos + offsetNormal * EPS;
      rd = normalize(nextDir);
      throughput *= hit.albedo;
      lastBounceSpecular = true;
    }

    if (max(throughput.r, max(throughput.g, throughput.b)) < 0.001) break;

    if (bounce >= MIN_BOUNCES_RR) {
      float pSurvive = clamp(max(throughput.r, max(throughput.g, throughput.b)), 0.05, 0.95);
      if (rand(rng) > pSurvive) break;
      throughput /= pSurvive;
    }
  }

  return radiance;
}

void main() {
  vec3 batchColorSum = vec3(0.0);
  float batchLum2Sum = 0.0;
  vec3 primaryNormal = vec3(0.0);
  float primaryDepth = -1.0;
  mat3 camRot = mat3(uCamMatrix);

  for (int s = 0; s < uSamplesPerFrame; s++) {
    uint rng = uint(gl_FragCoord.x);
    rng = pcgHash(rng) ^ uint(gl_FragCoord.y);
    rng = pcgHash(rng) ^ uint(uSampleCount + s);
    rng = pcgHash(rng);

    vec2 pixelCoord = floor(gl_FragCoord.xy) + vec2(rand(rng), rand(rng));
    vec2 ndc = (pixelCoord / uResolution) * 2.0 - 1.0;
    vec3 rayDir = normalize(camRot * normalize(vec3(ndc.x * uAspect * uTanHalfFov, ndc.y * uTanHalfFov, -1.0)));

    vec3 n0;
    float d0;
    vec3 c = tracePath(uCamPos, rayDir, rng, n0, d0);
    if (any(isnan(c)) || any(isinf(c))) c = vec3(0.0);

    batchColorSum += c;
    float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
    batchLum2Sum += lum * lum;

    if (s == 0) {
      primaryNormal = n0;
      primaryDepth = d0;
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
}