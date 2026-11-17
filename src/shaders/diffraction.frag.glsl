precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 vUv;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGBuffer;

uniform sampler2D uAccumTexture;
uniform sampler2D uWorldPhotonTex;
uniform vec2 uResolution;
uniform int uSampleCount;
uniform int uSamplesPerFrame;
uniform int uLaserMode;     // 0 = Verde 532nm, 1 = Vermelho 650nm, 2 = Violeta 405nm, 3 = Branco
uniform int uSlit1Blocked;  // 0 = Fenda 1 aberta, 1 = Fenda 1 tampada
uniform int uLaserSimMode;  // 0 = Híbrido (NEE Huygens), 1 = Fótons Reais (Atlas + Volumétrico)

uniform vec3 uCamPos;
uniform mat4 uCamMatrix;
uniform float uTanHalfFov;
uniform float uAspect;

const float PI = 3.14159265359;
const float INV_PI = 0.31830988618;
const float EPS = 0.0004;
const float T_MAX = 1e20;

const int MIN_BOUNCES_RR = 2;
const int MAX_BOUNCES = 8;

const int MAT_DIFFUSE = 0;
const int MAT_METAL = 1;
const int MAT_GLASS = 2;
const int MAT_GRATING = 3;
const int MAT_LIGHT = 4;
const int MAT_LASER_LENS = 5;

const int SURF_NONE = 0;
const int SURF_SCREEN = 1;
const int SURF_FLOOR = 2;
const int SURF_SLIT_PLATE = 3;
const int SURF_WALL_LEFT = 4;
const int SURF_WALL_BACK = 5;
const int SURF_WALL_RIGHT = 6;

// Luminária suave do laboratório
const vec3 LIGHT_MIN = vec3(0.15, 1.399, -0.25);
const vec3 LIGHT_MAX = vec3(0.95, 1.399, 0.55);
const vec3 LIGHT_NORMAL = vec3(0.0, -1.0, 0.0);
const float LIGHT_EMISSION = 6.5;
const float LIGHT_AREA = 0.80 * 0.80;

// Foco angular no teto para revelar os arcos arco-íris do CD em qualquer ângulo (inclusive de cima)
const vec3 SPOT_CENTER = vec3(1.35, 1.397, -0.55);
const float SPOT_HALF = 0.045;
const float SPOT_EMISSION = 420.0;
const float SPOT_VISIBLE_EMISSION = 18.0;
const float SPOT_AREA = (SPOT_HALF * 2.0) * (SPOT_HALF * 2.0);

const vec3 SLIT_CENTER = vec3(-1.10, -0.36, 0.05);
const vec3 SLIT_AXIS = vec3(0.34394, 0.0, -0.93899);
const vec3 SLIT_TANGENT = vec3(0.93899, 0.0, 0.34394);

const vec3 LASER_BACK = SLIT_CENTER - SLIT_AXIS * 1.05;
const vec3 LASER_TIP  = SLIT_CENTER - SLIT_AXIS * 0.56;
const vec3 LASER_MID  = SLIT_CENTER - SLIT_AXIS * 0.80;
const float LASER_RADIUS = 0.062;

const float SLIT1_MIN_U = -0.049;
const float SLIT1_MAX_U = -0.023;
const float SLIT2_MIN_U =  0.023;
const float SLIT2_MAX_U =  0.049;
const float SLIT_HALF_H =  0.15;

// Dimensões físicas do CD
const vec3 DISC_CENTER = vec3(0.55, -0.795, 0.30);
const float DISC_HOLE_R = 0.065;
const float DISC_HUB_R = 0.145;
const float DISC_DATA_R = 0.468;
const float DISC_OUTER_R = 0.480;
const float GRATING_PITCH_NM = 1600.0;

const vec3 GLASS_POS = vec3(0.45, -0.49, -0.38);
const float GLASS_R = 0.31;

const vec3 POST_POS = vec3(-0.78, -0.68, -0.76);
const float POST_R = 0.11;

struct HitInfo {
  float t;
  vec3 pos;
  vec3 normal;
  bool frontFace;
  vec3 albedo;
  float emission;
  float roughness;
  int matType;
  int surfaceId;
};

uint pcgHash(inout uint state) {
  state = state * 747796405u + 2891336453u;
  uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

float rand(inout uint state) {
  return float(pcgHash(state) >> 8u) * (1.0 / 16777216.0);
}

float cieGauss(float x, float mu, float sigma1, float sigma2) {
  float t = (x - mu) * (x < mu ? sigma1 : sigma2);
  return exp(-0.5 * t * t);
}

vec3 wavelengthToXYZ(float lambda) {
  float x = 1.056 * cieGauss(lambda, 599.8, 0.0264, 0.0323)
          + 0.362 * cieGauss(lambda, 442.0, 0.0624, 0.0374)
          - 0.065 * cieGauss(lambda, 501.1, 0.0490, 0.0382);
  float y = 0.821 * cieGauss(lambda, 568.8, 0.0213, 0.0247)
          + 0.286 * cieGauss(lambda, 530.9, 0.0613, 0.0322);
  float z = 1.217 * cieGauss(lambda, 437.0, 0.0845, 0.0278)
          + 0.681 * cieGauss(lambda, 459.0, 0.0385, 0.0725);
  return vec3(x, y, z);
}

const mat3 XYZ_TO_SRGB = mat3(
   3.2404542, -0.9692660,  0.0556434,
  -1.5371385,  1.8760108, -0.2040259,
  -0.4985314,  0.0415560,  1.0572252
);

vec3 wavelengthToLinearRGB(float lambda) {
  vec3 xyz = wavelengthToXYZ(lambda) * vec3(3.028, 3.179, 3.465);
  return XYZ_TO_SRGB * xyz;
}

float evalSpectrumFromRGB(vec3 rgb, float lambda) {
  float b = exp(-0.5 * pow((lambda - 450.0) / 32.0, 2.0));
  float g = exp(-0.5 * pow((lambda - 540.0) / 35.0, 2.0));
  float r = exp(-0.5 * pow((lambda - 625.0) / 38.0, 2.0));
  return dot(rgb, vec3(r, g, b)) / (r + g + b + 1e-5);
}

float sampleLaserWavelength(float roomLambda, inout uint rng) {
  if (uLaserMode == 0) return 532.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 1) return 650.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 2) return 405.0 + (rand(rng) - 0.5) * 3.0;
  return roomLambda;
}

void buildONB(vec3 n, out vec3 tangent, out vec3 bitangent) {
  float s = n.z >= 0.0 ? 1.0 : -1.0;
  float a = -1.0 / (s + n.z);
  float b = n.x * n.y * a;
  tangent = vec3(1.0 + s * n.x * n.x * a, s * b, -s * n.x);
  bitangent = vec3(b, s + n.y * n.y * a, -n.y);
}

vec3 sampleCosineHemisphere(vec3 n, inout uint rng) {
  float u1 = rand(rng);
  float u2 = rand(rng);
  float r = sqrt(u1);
  float phi = 2.0 * PI * u2;
  vec3 t, b;
  buildONB(n, t, b);
  return normalize(t * (r * cos(phi)) + b * (r * sin(phi)) + n * sqrt(max(0.0, 1.0 - u1)));
}

vec3 sampleGGXHalfVector(vec3 n, float alpha, inout uint rng) {
  float u1 = rand(rng);
  float u2 = rand(rng);
  float phi = 2.0 * PI * u1;
  float cosTheta = sqrt((1.0 - u2) / (1.0 + (alpha * alpha - 1.0) * u2));
  float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
  vec3 t, b;
  buildONB(n, t, b);
  return normalize(t * (sinTheta * cos(phi)) + b * (sinTheta * sin(phi)) + n * cosTheta);
}

float fresnelSchlickScalar(float cosTheta, float F0) {
  return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float smithG1(float NoX, float alpha2) {
  float NoX2 = NoX * NoX;
  return (2.0 * NoX) / (NoX + sqrt(alpha2 + (1.0 - alpha2) * NoX2));
}

bool intersectSphere(vec3 ro, vec3 rd, vec3 center, float radius, float tMax, out float tHit, out vec3 outwardNormal) {
  vec3 oc = ro - center;
  float b = dot(oc, rd);
  float c = dot(oc, oc) - radius * radius;
  float disc = b * b - c;
  if (disc < 0.0) return false;
  float sqrtDisc = sqrt(disc);
  float t = -b - sqrtDisc;
  if (t < EPS || t >= tMax) {
    t = -b + sqrtDisc;
    if (t < EPS || t >= tMax) return false;
  }
  tHit = t;
  outwardNormal = (ro + rd * t - center) / radius;
  return true;
}

bool intersectSphereAny(vec3 ro, vec3 rd, vec3 center, float radius, float tMax) {
  vec3 oc = ro - center;
  float b = dot(oc, rd);
  float c = dot(oc, oc) - radius * radius;
  float disc = b * b - c;
  if (disc < 0.0) return false;
  float sqrtDisc = sqrt(disc);
  float t = -b - sqrtDisc;
  if (t >= EPS && t < tMax) return true;
  t = -b + sqrtDisc;
  return (t >= EPS && t < tMax);
}

bool intersectCylinder(
  vec3 ro,
  vec3 rd,
  vec3 pA,
  vec3 pB,
  float radius,
  float tMax,
  out float tHit,
  out vec3 outwardNormal,
  out bool isFrontCap
) {
  vec3 ba = pB - pA;
  float baba = dot(ba, ba);
  vec3 oc = ro - pA;
  float bard = dot(ba, rd);
  float baoc = dot(ba, oc);

  float k2 = baba - bard * bard;
  if (k2 < 1e-6) return false;

  float k1 = baba * dot(oc, rd) - baoc * bard;
  float k0 = baba * dot(oc, oc) - baoc * baoc - radius * radius * baba;
  float h = k1 * k1 - k2 * k0;
  if (h < 0.0) return false;
  h = sqrt(h);

  float t = (-k1 - h) / k2;
  float y = baoc + t * bard;

  if (y > 0.0 && y < baba) {
    if (t < EPS || t >= tMax) return false;
    tHit = t;
    outwardNormal = normalize((oc + t * rd - ba * (y / baba)) / radius);
    isFrontCap = false;
    return true;
  }

  float tCap = ((y < 0.0 ? 0.0 : baba) - baoc) / bard;
  if (tCap >= EPS && tCap < tMax && abs(k1 + k2 * tCap) < h) {
    tHit = tCap;
    outwardNormal = normalize(ba) * (y < 0.0 ? -1.0 : 1.0);
    isFrontCap = (y >= baba);
    return true;
  }

  return false;
}

bool intersectQuadX(vec3 ro, vec3 rd, float planeX, float normalX, vec2 minYZ, vec2 maxYZ, float tMax, out float tHit) {
  if (rd.x * normalX >= -1e-6) return false;
  float t = (planeX - ro.x) / rd.x;
  if (t < EPS || t >= tMax) return false;
  vec3 p = ro + rd * t;
  if (p.y < minYZ.x || p.y > maxYZ.x || p.z < minYZ.y || p.z > maxYZ.y) return false;
  tHit = t;
  return true;
}

bool intersectQuadY(vec3 ro, vec3 rd, float planeY, float normalY, vec2 minXZ, vec2 maxXZ, float tMax, out float tHit) {
  if (rd.y * normalY >= -1e-6) return false;
  float t = (planeY - ro.y) / rd.y;
  if (t < EPS || t >= tMax) return false;
  vec3 p = ro + rd * t;
  if (p.x < minXZ.x || p.x > maxXZ.x || p.z < minXZ.y || p.z > maxXZ.y) return false;
  tHit = t;
  return true;
}

bool intersectQuadZ(vec3 ro, vec3 rd, float planeZ, float normalZ, vec2 minXY, vec2 maxXY, float tMax, out float tHit) {
  if (rd.z * normalZ >= -1e-6) return false;
  float t = (planeZ - ro.z) / rd.z;
  if (t < EPS || t >= tMax) return false;
  vec3 p = ro + rd * t;
  if (p.x < minXY.x || p.x > maxXY.x || p.y < minXY.y || p.y > maxXY.y) return false;
  tHit = t;
  return true;
}

bool intersectSlitPlate(vec3 ro, vec3 rd, float tMax, out float tHit, out vec3 outwardN, out bool isShutter) {
  float denom = dot(rd, SLIT_AXIS);
  if (abs(denom) < 1e-6) return false;
  float t = dot(SLIT_CENTER - ro, SLIT_AXIS) / denom;
  if (t < EPS || t >= tMax) return false;

  vec3 p = ro + rd * t;
  vec3 rel = p - SLIT_CENTER;
  float u = dot(rel, SLIT_TANGENT);
  float v = rel.y;

  if (abs(u) > 0.25 || abs(v) > 0.44) return false;

  bool inSlit1 = (u >= SLIT1_MIN_U && u <= SLIT1_MAX_U && abs(v) <= SLIT_HALF_H);
  bool inSlit2 = (u >= SLIT2_MIN_U && u <= SLIT2_MAX_U && abs(v) <= SLIT_HALF_H);

  if (inSlit2) return false;
  if (inSlit1 && uSlit1Blocked == 0) return false;

  tHit = t;
  outwardN = SLIT_AXIS;
  isShutter = inSlit1;
  return true;
}

bool intersectDisc(vec3 ro, vec3 rd, float tMax, out float tHit, out float radialDist) {
  if (rd.y >= -1e-6) return false;
  float t = (DISC_CENTER.y - ro.y) / rd.y;
  if (t < EPS || t >= tMax) return false;
  vec3 p = ro + rd * t;
  vec2 d = p.xz - DISC_CENTER.xz;
  float r = length(d);
  if (r < DISC_HOLE_R || r > DISC_OUTER_R) return false;
  tHit = t;
  radialDist = r;
  return true;
}

bool traceShadow(vec3 ro, vec3 rd, float maxDist) {
  if (intersectSphereAny(ro, rd, GLASS_POS, GLASS_R, maxDist)) return true;
  if (intersectSphereAny(ro, rd, POST_POS, POST_R, maxDist)) return true;
  return false;
}

void setHitSurface(
  inout HitInfo hit,
  float t,
  vec3 ro,
  vec3 rd,
  vec3 outwardNormal,
  vec3 albedo,
  float emission,
  float roughness,
  int matType,
  int surfaceId
) {
  hit.t = t;
  hit.pos = ro + rd * t;
  hit.frontFace = dot(rd, outwardNormal) < 0.0;
  hit.normal = hit.frontFace ? outwardNormal : -outwardNormal;
  hit.albedo = albedo;
  hit.emission = emission;
  hit.roughness = roughness;
  hit.matType = matType;
  hit.surfaceId = surfaceId;
}

bool traceScene(vec3 ro, vec3 rd, float maxDist, out HitInfo hit) {
  hit.t = maxDist;
  hit.surfaceId = SURF_NONE;
  bool anyHit = false;
  float t;
  vec3 n;

  // Foco de luz visível no teto (emissão visual controlada para evitar fireflies no bounce especular)
  if (intersectQuadY(ro, rd, SPOT_CENTER.y, -1.0, SPOT_CENTER.xz - SPOT_HALF, SPOT_CENTER.xz + SPOT_HALF, hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, LIGHT_NORMAL, vec3(0.0), SPOT_VISIBLE_EMISSION, 0.0, MAT_LIGHT, SURF_NONE);
  }

  if (intersectQuadY(ro, rd, 1.399, -1.0, LIGHT_MIN.xz, LIGHT_MAX.xz, hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, LIGHT_NORMAL, vec3(0.0), LIGHT_EMISSION, 0.0, MAT_LIGHT, SURF_NONE);
  }

  if (intersectQuadY(ro, rd, -0.8, 1.0, vec2(-1.8, -1.4), vec2(1.8, 1.8), hit.t, t)) {
    anyHit = true;
    vec3 p = ro + rd * t;
    vec2 g = abs(fract(p.xz * 4.0) - 0.5);
    float line = (g.x > 0.46 || g.y > 0.46) ? 0.06 : 0.13;
    setHitSurface(hit, t, ro, rd, vec3(0.0, 1.0, 0.0), vec3(line, line * 1.05, line * 1.15), 0.0, 1.0, MAT_DIFFUSE, SURF_FLOOR);
  }

  if (intersectQuadZ(ro, rd, -1.318, 1.0, vec2(-1.60, -0.80), vec2(0.18, 0.55), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(0.0, 0.0, 1.0), vec3(0.90), 0.0, 1.0, MAT_DIFFUSE, SURF_SCREEN);
  }

  if (intersectQuadZ(ro, rd, -1.4, 1.0, vec2(-1.8, -0.8), vec2(1.8, 1.4), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(0.0, 0.0, 1.0), vec3(0.10), 0.0, 1.0, MAT_DIFFUSE, SURF_WALL_BACK);
  }
  if (intersectQuadY(ro, rd, 1.4, -1.0, vec2(-1.8, -1.4), vec2(1.8, 1.8), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(0.0, -1.0, 0.0), vec3(0.09), 0.0, 1.0, MAT_DIFFUSE, SURF_NONE);
  }
  if (intersectQuadX(ro, rd, -1.8, 1.0, vec2(-0.8, -1.4), vec2(1.4, 1.8), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(1.0, 0.0, 0.0), vec3(0.10), 0.0, 1.0, MAT_DIFFUSE, SURF_WALL_LEFT);
  }
  if (intersectQuadX(ro, rd, 1.8, -1.0, vec2(-0.8, -1.4), vec2(1.4, 1.8), hit.t, t)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, vec3(-1.0, 0.0, 0.0), vec3(0.10), 0.0, 1.0, MAT_DIFFUSE, SURF_WALL_RIGHT);
  }

  bool isFrontCap;
  if (intersectCylinder(ro, rd, LASER_BACK, LASER_TIP, LASER_RADIUS, hit.t, t, n, isFrontCap)) {
    anyHit = true;
    vec3 p = ro + rd * t;
    if (isFrontCap && length(p - LASER_TIP) < 0.022) {
      setHitSurface(hit, t, ro, rd, n, vec3(0.0), 18.0, 0.0, MAT_LASER_LENS, SURF_NONE);
    } else if (isFrontCap && length(p - LASER_TIP) < 0.042) {
      setHitSurface(hit, t, ro, rd, n, vec3(0.85, 0.65, 0.25), 0.0, 0.18, MAT_METAL, SURF_NONE);
    } else {
      setHitSurface(hit, t, ro, rd, n, vec3(0.16, 0.17, 0.20), 0.0, 0.28, MAT_METAL, SURF_NONE);
    }
  }

  if (intersectCylinder(ro, rd, vec3(LASER_MID.x, -0.80, LASER_MID.z), LASER_MID, 0.024, hit.t, t, n, isFrontCap)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, n, vec3(0.25, 0.26, 0.30), 0.0, 0.30, MAT_METAL, SURF_NONE);
  }

  bool isShutter;
  if (intersectSlitPlate(ro, rd, hit.t, t, n, isShutter)) {
    anyHit = true;
    if (isShutter) {
      setHitSurface(hit, t, ro, rd, n, vec3(0.75, 0.22, 0.18), 0.0, 0.35, MAT_DIFFUSE, SURF_SLIT_PLATE);
    } else {
      setHitSurface(hit, t, ro, rd, n, vec3(0.12, 0.13, 0.15), 0.0, 0.25, MAT_DIFFUSE, SURF_SLIT_PLATE);
    }
  }

  float radialDist;
  if (intersectDisc(ro, rd, hit.t, t, radialDist)) {
    anyHit = true;
    if (radialDist < DISC_HUB_R) {
      setHitSurface(hit, t, ro, rd, vec3(0.0, 1.0, 0.0), vec3(0.08, 0.085, 0.095), 0.0, 0.05, MAT_METAL, SURF_NONE);
    } else if (radialDist > DISC_DATA_R) {
      setHitSurface(hit, t, ro, rd, vec3(0.0, 1.0, 0.0), vec3(0.24), 0.0, 0.04, MAT_METAL, SURF_NONE);
    } else {
      setHitSurface(hit, t, ro, rd, vec3(0.0, 1.0, 0.0), vec3(0.92), 0.0, 0.055, MAT_GRATING, SURF_NONE);
    }
  }

  if (intersectSphere(ro, rd, GLASS_POS, GLASS_R, hit.t, t, n)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, n, vec3(0.98), 0.0, 0.0, MAT_GLASS, SURF_NONE);
  }

  if (intersectSphere(ro, rd, POST_POS, POST_R, hit.t, t, n)) {
    anyHit = true;
    setHitSurface(hit, t, ro, rd, n, vec3(0.85, 0.86, 0.88), 0.0, 0.15, MAT_METAL, SURF_NONE);
  }

  return anyHit;
}

vec3 sampleWorldPhotonMap(HitInfo hit) {
  vec2 uv = vec2(-1.0);
  if (hit.surfaceId == SURF_SCREEN) {
    float su = (hit.pos.x + 1.60) / 1.78;
    float sv = (hit.pos.y + 0.80) / 1.35;
    uv = vec2(0.02 + su * 0.46, 0.52 + sv * 0.46);
  } else if (hit.surfaceId == SURF_FLOOR) {
    float su = (hit.pos.x + 1.80) / 3.60;
    float sv = (hit.pos.z + 1.40) / 3.20;
    uv = vec2(0.52 + su * 0.46, 0.52 + sv * 0.46);
  } else if (hit.surfaceId == SURF_SLIT_PLATE) {
    if (dot(hit.normal, -SLIT_AXIS) < 0.5) return vec3(0.0);
    vec3 rel = hit.pos - SLIT_CENTER;
    float su = (dot(rel, SLIT_TANGENT) + 0.25) / 0.50;
    float sv = (rel.y + 0.44) / 0.88;
    uv = vec2(0.02 + su * 0.46, 0.02 + sv * 0.46);
  } else if (hit.surfaceId == SURF_WALL_LEFT) {
    float su = (hit.pos.z + 1.40) / 3.20;
    float sv = (hit.pos.y + 0.80) / 2.20;
    uv = vec2(0.51 + su * 0.14, 0.02 + sv * 0.46);
  } else if (hit.surfaceId == SURF_WALL_BACK) {
    float su = (hit.pos.x + 1.80) / 3.60;
    float sv = (hit.pos.y + 0.80) / 2.20;
    uv = vec2(0.68 + su * 0.14, 0.02 + sv * 0.46);
  } else if (hit.surfaceId == SURF_WALL_RIGHT) {
    float su = (hit.pos.z + 1.40) / 3.20;
    float sv = (hit.pos.y + 0.80) / 2.20;
    uv = vec2(0.85 + su * 0.14, 0.02 + sv * 0.46);
  }

  if (uv.x < 0.0) return vec3(0.0);
  return texture(uWorldPhotonTex, uv).rgb;
}

float sampleOverheadLight(HitInfo hit, float lambda, inout uint rng) {
  float lx = mix(LIGHT_MIN.x, LIGHT_MAX.x, rand(rng));
  float lz = mix(LIGHT_MIN.z, LIGHT_MAX.z, rand(rng));
  vec3 lightPos = vec3(lx, LIGHT_MIN.y, lz);

  vec3 toLight = lightPos - hit.pos;
  float dist2 = dot(toLight, toLight);
  float dist = sqrt(dist2);
  vec3 L = toLight / dist;

  float cosSurf = dot(hit.normal, L);
  float cosLight = dot(LIGHT_NORMAL, -L);
  if (cosSurf <= 0.0 || cosLight <= 0.0) return 0.0;

  if (traceShadow(hit.pos + hit.normal * EPS, L, dist - EPS * 2.0)) return 0.0;

  float geom = (cosSurf * cosLight) / dist2;
  float refl = evalSpectrumFromRGB(hit.albedo, lambda);
  return (refl * INV_PI) * LIGHT_EMISSION * geom * LIGHT_AREA;
}

// Difração nítida em leques de CD (iluminada pelo foco inclinado + sutil base de alumínio)
float sampleGratingDiffraction(HitInfo hit, vec3 V, float lambda, inout uint rng) {
  vec2 d = hit.pos.xz - DISC_CENTER.xz;
  float lenD = length(d);
  if (lenD < 1e-5) return 0.0;

  vec3 R = vec3(d.x / lenD, 0.0, d.y / lenD);
  vec3 T = vec3(-R.z, 0.0, R.x);

  float sx = SPOT_CENTER.x + (rand(rng) * 2.0 - 1.0) * SPOT_HALF;
  float sz = SPOT_CENTER.z + (rand(rng) * 2.0 - 1.0) * SPOT_HALF;
  vec3 spotPos = vec3(sx, SPOT_CENTER.y, sz);

  vec3 toSpot = spotPos - hit.pos;
  float dist2 = dot(toSpot, toSpot);
  float dist = sqrt(dist2);
  vec3 L = toSpot / dist;

  float cosSurf = L.y;
  float cosLight = -L.y;
  float rainbow = 0.0;

  if (cosSurf > 0.0 && cosLight > 0.0 && !traceShadow(hit.pos + vec3(0.0, EPS, 0.0), L, dist - EPS * 2.0)) {
    vec3 Hvec = L + V;
    float u = dot(R, Hvec);
    float v = dot(T, Hvec);

    float diffracted = 0.0;
    for (int m = -2; m <= 2; m++) {
      if (m == 0) continue;
      float uTarget = float(m) * (lambda / GRATING_PITCH_NM);
      float du = u - uTarget;
      float orderWeight = (abs(m) == 1) ? 24.0 : 11.0;
      // sigmaU = 0.020 (cores puras e nítidas); sigmaV = 0.18 (asas largas de CD visíveis de qualquer ângulo)
      diffracted += orderWeight * exp(-0.5 * ((du * du) / (0.020 * 0.020) + (v * v) / (0.18 * 0.18)));
    }

    float geom = (cosSurf * cosLight) / dist2;
    rainbow = diffracted * SPOT_EMISSION * geom * SPOT_AREA;
  }

  // Leve brilho prateado da camada de alumínio sob a luz ambiente da sala
  HitInfo sheenHit = hit;
  sheenHit.albedo = vec3(0.075);
  float aluminumSheen = sampleOverheadLight(sheenHit, lambda, rng);

  return rainbow + aluminumSheen;
}

float sampleDoubleSlitHuygens(
  vec3 targetPos,
  vec3 surfaceNormal,
  bool isSurface,
  float laserLambda,
  int nSubPerSlit,
  inout uint rng
) {
  vec3 toTargetFromCenter = targetPos - SLIT_CENTER;
  float dRef = length(toTargetFromCenter);
  if (dRef < 0.05) return 0.0;

  vec3 dirCenter = toTargetFromCenter / dRef;
  float cosAxis = dot(dirCenter, SLIT_AXIS);
  if (cosAxis <= 0.05) return 0.0;

  float cosSurf = 1.0;
  if (isSurface) {
    cosSurf = dot(surfaceNormal, -dirCenter);
    if (cosSurf <= 0.0) return 0.0;
  }

  float dy = targetPos.y - SLIT_CENTER.y;
  if (abs(dy) > 0.36) return 0.0;
  float verticalBeam = exp(-0.5 * (dy * dy) / (0.11 * 0.11));

  float vSlit = clamp(dy * 0.55 + (rand(rng) - 0.5) * 0.06, -SLIT_HALF_H, SLIT_HALF_H);
  float lambdaSim = (laserLambda / 550.0) * 0.0054;
  float k = (2.0 * PI) / lambdaSim;

  vec2 phasor = vec2(0.0);
  float invN = 1.0 / float(nSubPerSlit);
  vec3 shadowStart = isSurface ? (targetPos + surfaceNormal * EPS) : targetPos;

  if (uSlit1Blocked == 0) {
    for (int i = 0; i < nSubPerSlit; i++) {
      float tStrat = (float(i) + rand(rng)) * invN;
      float u = mix(SLIT1_MIN_U, SLIT1_MAX_U, tStrat);
      vec3 slitPt = SLIT_CENTER + SLIT_TANGENT * u + vec3(0.0, vSlit, 0.0);

      vec3 toSlit = slitPt - shadowStart;
      float dOut = length(toSlit);
      vec3 L = toSlit / dOut;

      if (!traceShadow(shadowStart, L, dOut - 0.015)) {
        float dIn = length(slitPt - LASER_TIP) - 0.56;
        float phase = k * ((dIn + dOut) - dRef);
        float amp = ((1.0 + cosAxis) * 0.5) * invN / max(dOut, 0.25);
        phasor += vec2(cos(phase), sin(phase)) * amp;
      }
    }
  }

  for (int i = 0; i < nSubPerSlit; i++) {
    float tStrat = (float(i) + rand(rng)) * invN;
    float u = mix(SLIT2_MIN_U, SLIT2_MAX_U, tStrat);
    vec3 slitPt = SLIT_CENTER + SLIT_TANGENT * u + vec3(0.0, vSlit, 0.0);

    vec3 toSlit = slitPt - shadowStart;
    float dOut = length(toSlit);
    vec3 L = toSlit / dOut;

    if (!traceShadow(shadowStart, L, dOut - 0.015)) {
      float dIn = length(slitPt - LASER_TIP) - 0.56;
      float phase = k * ((dIn + dOut) - dRef);
      float amp = ((1.0 + cosAxis) * 0.5) * invN / max(dOut, 0.25);
      phasor += vec2(cos(phase), sin(phase)) * amp;
    }
  }

  return dot(phasor, phasor) * verticalBeam * cosSurf;
}

float evalPreSlitLaserBeam(vec3 ro, vec3 rd, float maxT) {
  vec3 w = ro - LASER_TIP;
  float segLen = length(SLIT_CENTER - LASER_TIP);
  float b = dot(rd, SLIT_AXIS);
  float d = dot(rd, w);
  float e = dot(SLIT_AXIS, w);
  float denom = 1.0 - b * b;

  float tc = (denom < 1e-5) ? e : (e - b * d) / denom;
  tc = clamp(tc, 0.0, segLen);
  float sc = max(0.0, -d + tc * b);
  if (sc >= maxT) return 0.0;

  vec3 pRay = ro + rd * sc;
  vec3 pSeg = LASER_TIP + SLIT_AXIS * tc;
  float dist = length(pRay - pSeg);

  float core = exp(-(dist * dist) / (0.011 * 0.011));
  float halo = 0.20 * exp(-(dist * dist) / (0.032 * 0.032));
  return (core + halo) * 0.95 / max(sqrt(max(denom, 0.0)), 0.25);
}

float evalPostSlitVolumetricFan(vec3 ro, vec3 rd, float maxT, float laserLambda, inout uint rng) {
  if (abs(rd.y) < 1e-5) {
    if (abs(ro.y - SLIT_CENTER.y) > 0.24) return 0.0;
  }

  float yMin = SLIT_CENTER.y - 0.22;
  float yMax = SLIT_CENTER.y + 0.22;
  float t0 = 0.0;
  float t1 = min(maxT, 6.0);

  if (abs(rd.y) >= 1e-5) {
    float ty0 = (yMin - ro.y) / rd.y;
    float ty1 = (yMax - ro.y) / rd.y;
    t0 = max(t0, min(ty0, ty1));
    t1 = min(t1, max(ty0, ty1));
  }

  float slabLen = t1 - t0;
  if (slabLen <= 0.005) return 0.0;

  const int VOL_STEPS = 3;
  float stepLen = slabLen / float(VOL_STEPS);
  float sumVol = 0.0;

  for (int i = 0; i < VOL_STEPS; i++) {
    float tSample = t0 + (float(i) + rand(rng)) * stepLen;
    vec3 pVol = ro + rd * tSample;
    sumVol += sampleDoubleSlitHuygens(pVol, vec3(0.0), false, laserLambda, 4, rng);
  }

  return (sumVol / float(VOL_STEPS)) * slabLen * 0.14;
}

vec3 tracePath(vec3 ro, vec3 rd, float roomLambda, float laserLambda, inout uint rng, out vec3 primaryNormal, out float primaryDepth) {
  vec3 radianceRGB = vec3(0.0);
  float throughput = 1.0;
  bool lastBounceSpecular = true;

  primaryNormal = vec3(0.0);
  primaryDepth = -1.0;

  vec3 roomSpectrumRGB = wavelengthToLinearRGB(roomLambda);
  vec3 laserSpectrumRGB = wavelengthToLinearRGB(laserLambda);
  float laserGain = (uLaserMode == 3) ? 1.8 : 0.95;

  for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {
    HitInfo hit;
    bool hasHit = traceScene(ro, rd, T_MAX, hit);
    float segMaxT = hasHit ? hit.t : 8.0;

    if (uLaserSimMode == 0 && bounce == 0) {
      float preBeam = evalPreSlitLaserBeam(ro, rd, segMaxT);
      float postFan = evalPostSlitVolumetricFan(ro, rd, segMaxT, laserLambda, rng);
      radianceRGB += laserSpectrumRGB * ((preBeam + postFan * 1.4) * laserGain);
    }

    if (!hasHit) {
      radianceRGB += roomSpectrumRGB * (throughput * 0.010);
      break;
    }

    if (bounce == 0) {
      primaryNormal = hit.normal;
      primaryDepth = hit.t;
    }

    if (hit.matType == MAT_LIGHT) {
      if (lastBounceSpecular) {
        radianceRGB += roomSpectrumRGB * (throughput * hit.emission);
      }
      break;
    }

    if (hit.matType == MAT_LASER_LENS) {
      if (lastBounceSpecular) {
        radianceRGB += laserSpectrumRGB * (throughput * hit.emission * 0.35);
      }
      break;
    }

    if (hit.matType == MAT_DIFFUSE) {
      float roomDirect = sampleOverheadLight(hit, roomLambda, rng);
      radianceRGB += roomSpectrumRGB * (throughput * roomDirect);

      if (uLaserSimMode == 0) {
        float laserHuygens = sampleDoubleSlitHuygens(hit.pos, hit.normal, true, laserLambda, 6, rng);
        float reflLaser = evalSpectrumFromRGB(hit.albedo, laserLambda);
        radianceRGB += laserSpectrumRGB * (throughput * reflLaser * INV_PI * laserHuygens * 5.2 * laserGain);
      } else if (hit.surfaceId != SURF_NONE) {
        radianceRGB += throughput * sampleWorldPhotonMap(hit);
      }

      ro = hit.pos + hit.normal * EPS;
      rd = sampleCosineHemisphere(hit.normal, rng);
      throughput *= evalSpectrumFromRGB(hit.albedo, roomLambda);
      lastBounceSpecular = false;
    } else if (hit.matType == MAT_GRATING) {
      float gratingDirect = sampleGratingDiffraction(hit, -rd, roomLambda, rng);
      radianceRGB += roomSpectrumRGB * (throughput * gratingDirect);

      float alpha = max(hit.roughness * hit.roughness, 0.003);
      float alpha2 = alpha * alpha;
      vec3 V = -rd;
      vec3 H = sampleGGXHalfVector(hit.normal, alpha, rng);
      vec3 L = reflect(-V, H);

      float NoL = dot(hit.normal, L);
      float NoV = dot(hit.normal, V);
      float NoH = dot(hit.normal, H);
      float VoH = dot(V, H);
      if (NoL <= 0.0 || NoV <= 1e-5 || NoH <= 1e-5 || VoH <= 0.0) break;

      float F = fresnelSchlickScalar(VoH, 0.86);
      float G = smithG1(NoV, alpha2) * smithG1(NoL, alpha2);
      float weight = F * ((G * VoH) / (NoH * NoV));

      ro = hit.pos + hit.normal * EPS;
      rd = normalize(L);
      throughput *= clamp(weight, 0.0, 1.0);
      lastBounceSpecular = true;
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

      float F = fresnelSchlickScalar(VoH, evalSpectrumFromRGB(hit.albedo, roomLambda));
      float G = smithG1(NoV, alpha2) * smithG1(NoL, alpha2);
      float weight = F * ((G * VoH) / (NoH * NoV));

      ro = hit.pos + hit.normal * EPS;
      rd = normalize(L);
      throughput *= clamp(weight, 0.0, 1.0);
      lastBounceSpecular = true;
    } else if (hit.matType == MAT_GLASS) {
      float lamUm = roomLambda * 0.001;
      float ior = 1.49 + 0.015 / (lamUm * lamUm);

      float eta = hit.frontFace ? (1.0 / ior) : ior;
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
      throughput *= 0.98;
      lastBounceSpecular = true;
    }

    if (throughput < 0.001) break;

    if (bounce >= MIN_BOUNCES_RR) {
      float pSurvive = clamp(throughput, 0.05, 0.95);
      if (rand(rng) > pSurvive) break;
      throughput /= pSurvive;
    }
  }

  return radianceRGB;
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

    vec2 jitter = vec2(rand(rng), rand(rng));
    vec2 pixelCoord = floor(gl_FragCoord.xy) + jitter;
    vec2 ndc = (pixelCoord / uResolution) * 2.0 - 1.0;

    vec3 localDir = normalize(vec3(ndc.x * uAspect * uTanHalfFov, ndc.y * uTanHalfFov, -1.0));
    vec3 rayDir = normalize(camRot * localDir);

    float roomLambda = mix(380.0, 720.0, rand(rng));
    float laserLambda = sampleLaserWavelength(roomLambda, rng);

    vec3 n0;
    float d0;
    vec3 sampleColor = tracePath(uCamPos, rayDir, roomLambda, laserLambda, rng, n0, d0);

    if (any(isnan(sampleColor)) || any(isinf(sampleColor))) {
      sampleColor = vec3(0.0);
    }

    batchColorSum += sampleColor;
    float lum = max(dot(sampleColor, vec3(0.2126, 0.7152, 0.0722)), 0.0);
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