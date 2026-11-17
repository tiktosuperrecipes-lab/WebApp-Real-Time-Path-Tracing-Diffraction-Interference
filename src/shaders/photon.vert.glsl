precision highp float;
precision highp int;

in float aIndex;

uniform mat4 uViewProj;
uniform vec3 uCamPos;
uniform vec2 uResolution;
uniform float uTanHalfFov;
uniform int uFrameSeed;
uniform int uLaserMode;
uniform int uSlit1Blocked;
uniform int uPhotonCount;
uniform int uPassType; // 0 = Superfícies (Atlas 3D 1024x1024), 1 = Poeira Volumétrica no Ar (Tela)

out vec3 vColor;
out float vCamDist;

const float PI = 3.14159265359;
const float INV_PI = 0.31830988618;
const float EPS = 0.0005;
const float T_MAX = 1e20;
const float ATLAS_SIZE = 1024.0;

const vec3 SLIT_CENTER = vec3(-1.10, -0.36, 0.05);
const vec3 SLIT_AXIS = vec3(0.34394, 0.0, -0.93899);
const vec3 SLIT_TANGENT = vec3(0.93899, 0.0, 0.34394);
const vec3 LASER_TIP = SLIT_CENTER - SLIT_AXIS * 0.56;

const float SLIT1_MIN_U = -0.049;
const float SLIT1_MAX_U = -0.023;
const float SLIT2_MIN_U =  0.023;
const float SLIT2_MAX_U =  0.049;
const float SLIT_HALF_H =  0.15;

const vec3 GLASS_POS = vec3(0.45, -0.49, -0.38);
const float GLASS_R = 0.31;

const vec3 POST_POS = vec3(-0.78, -0.68, -0.76);
const float POST_R = 0.11;

const int HIT_NONE = 0;
const int HIT_DIFFUSE = 1;
const int HIT_METAL = 2;
const int HIT_GLASS = 3;
const int HIT_SLIT_OPEN = 4;
const int HIT_SLIT_SOLID = 5;

const int SURF_NONE = 0;
const int SURF_SCREEN = 1;
const int SURF_FLOOR = 2;
const int SURF_SLIT_PLATE = 3;
const int SURF_WALL_LEFT = 4;
const int SURF_WALL_BACK = 5;
const int SURF_WALL_RIGHT = 6;

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
  return max(XYZ_TO_SRGB * xyz, vec3(0.0));
}

float evalSpectrumFromRGB(vec3 rgb, float lambda) {
  float b = exp(-0.5 * pow((lambda - 450.0) / 32.0, 2.0));
  float g = exp(-0.5 * pow((lambda - 540.0) / 35.0, 2.0));
  float r = exp(-0.5 * pow((lambda - 625.0) / 38.0, 2.0));
  return dot(rgb, vec3(r, g, b)) / (r + g + b + 1e-5);
}

float sampleLaserWavelength(inout uint rng) {
  if (uLaserMode == 0) return 532.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 1) return 650.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 2) return 405.0 + (rand(rng) - 0.5) * 3.0;
  return mix(380.0, 720.0, rand(rng));
}

bool intersectSphere(vec3 ro, vec3 rd, vec3 center, float radius, float tMax, out float tHit, out vec3 outwardN) {
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
  outwardN = (ro + rd * t - center) / radius;
  return true;
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

struct PhotonHit {
  float t;
  vec3 pos;
  vec3 normal;
  bool frontFace;
  vec3 albedo;
  int type;
  int surfaceId;
};

PhotonHit traceForward(vec3 ro, vec3 rd, bool checkSlitPlate) {
  PhotonHit hit;
  hit.t = T_MAX;
  hit.type = HIT_NONE;
  hit.surfaceId = SURF_NONE;
  float t;
  vec3 n;

  if (checkSlitPlate) {
    float denom = dot(rd, SLIT_AXIS);
    if (abs(denom) > 1e-6) {
      float tPlate = dot(SLIT_CENTER - ro, SLIT_AXIS) / denom;
      if (tPlate > EPS && tPlate < hit.t) {
        vec3 p = ro + rd * tPlate;
        vec3 rel = p - SLIT_CENTER;
        float u = dot(rel, SLIT_TANGENT);
        float v = rel.y;
        if (abs(u) <= 0.25 && abs(v) <= 0.44) {
          bool inSlit1 = (u >= SLIT1_MIN_U && u <= SLIT1_MAX_U && abs(v) <= SLIT_HALF_H);
          bool inSlit2 = (u >= SLIT2_MIN_U && u <= SLIT2_MAX_U && abs(v) <= SLIT_HALF_H);
          hit.t = tPlate;
          hit.pos = p;
          hit.frontFace = denom < 0.0;
          hit.normal = hit.frontFace ? SLIT_AXIS : -SLIT_AXIS;
          hit.surfaceId = SURF_SLIT_PLATE;

          if (inSlit2 || (inSlit1 && uSlit1Blocked == 0)) {
            hit.type = HIT_SLIT_OPEN;
            hit.albedo = vec3(1.0);
          } else {
            hit.type = HIT_SLIT_SOLID;
            hit.albedo = inSlit1 ? vec3(0.75, 0.22, 0.18) : vec3(0.28, 0.30, 0.34);
          }
        }
      }
    }
  }

  if (intersectSphere(ro, rd, GLASS_POS, GLASS_R, hit.t, t, n)) {
    hit.t = t; hit.pos = ro + rd * t;
    hit.frontFace = dot(rd, n) < 0.0;
    hit.normal = hit.frontFace ? n : -n;
    hit.albedo = vec3(0.98);
    hit.type = HIT_GLASS;
    hit.surfaceId = SURF_NONE;
  }

  if (intersectSphere(ro, rd, POST_POS, POST_R, hit.t, t, n)) {
    hit.t = t; hit.pos = ro + rd * t;
    hit.frontFace = dot(rd, n) < 0.0;
    hit.normal = hit.frontFace ? n : -n;
    hit.albedo = vec3(0.85, 0.86, 0.88);
    hit.type = HIT_METAL;
    hit.surfaceId = SURF_NONE;
  }

  if (intersectQuadY(ro, rd, -0.8, 1.0, vec2(-1.8, -1.4), vec2(1.8, 1.8), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t;
    hit.normal = vec3(0.0, 1.0, 0.0); hit.frontFace = true;
    vec2 g = abs(fract(hit.pos.xz * 4.0) - 0.5);
    float line = (g.x > 0.46 || g.y > 0.46) ? 0.06 : 0.13;
    hit.albedo = vec3(line, line * 1.05, line * 1.15);
    hit.type = HIT_DIFFUSE;
    hit.surfaceId = SURF_FLOOR;
  }

  if (intersectQuadZ(ro, rd, -1.318, 1.0, vec2(-1.60, -0.80), vec2(0.18, 0.55), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t;
    hit.normal = vec3(0.0, 0.0, 1.0); hit.frontFace = true;
    hit.albedo = vec3(0.90);
    hit.type = HIT_DIFFUSE;
    hit.surfaceId = SURF_SCREEN;
  }

  if (intersectQuadZ(ro, rd, -1.4, 1.0, vec2(-1.8, -0.8), vec2(1.8, 1.4), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t; hit.normal = vec3(0.0, 0.0, 1.0); hit.frontFace = true;
    hit.albedo = vec3(0.10); hit.type = HIT_DIFFUSE; hit.surfaceId = SURF_WALL_BACK;
  }
  if (intersectQuadY(ro, rd, 1.4, -1.0, vec2(-1.8, -1.4), vec2(1.8, 1.8), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t; hit.normal = vec3(0.0, -1.0, 0.0); hit.frontFace = true;
    hit.albedo = vec3(0.09); hit.type = HIT_DIFFUSE; hit.surfaceId = SURF_NONE;
  }
  if (intersectQuadX(ro, rd, -1.8, 1.0, vec2(-0.8, -1.4), vec2(1.4, 1.8), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t; hit.normal = vec3(1.0, 0.0, 0.0); hit.frontFace = true;
    hit.albedo = vec3(0.10); hit.type = HIT_DIFFUSE; hit.surfaceId = SURF_WALL_LEFT;
  }
  if (intersectQuadX(ro, rd, 1.8, -1.0, vec2(-0.8, -1.4), vec2(1.4, 1.8), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t; hit.normal = vec3(-1.0, 0.0, 0.0); hit.frontFace = true;
    hit.albedo = vec3(0.10); hit.type = HIT_DIFFUSE; hit.surfaceId = SURF_WALL_RIGHT;
  }

  return hit;
}

float evalOpenSlitsWaveWeight(float sinTheta, float laserLambda) {
  float lambdaSim = (laserLambda / 550.0) * 0.0054;
  float k = (2.0 * PI) / lambdaSim;

  vec2 phasor = vec2(0.0);
  float invN = 1.0 / 6.0;

  if (uSlit1Blocked == 0) {
    for (int i = 0; i < 6; i++) {
      float u = mix(SLIT1_MIN_U, SLIT1_MAX_U, (float(i) + 0.5) * invN);
      float phase = -k * u * sinTheta;
      phasor += vec2(cos(phase), sin(phase)) * invN;
    }
  }

  for (int i = 0; i < 6; i++) {
    float u = mix(SLIT2_MIN_U, SLIT2_MAX_U, (float(i) + 0.5) * invN);
    float phase = -k * u * sinTheta;
    phasor += vec2(cos(phase), sin(phase)) * invN;
  }

  return dot(phasor, phasor);
}

void discardPhoton() {
  gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
  gl_PointSize = 1.0;
  vColor = vec3(0.0);
  vCamDist = 1e9;
}

void emitAirSplat(vec3 worldPos, vec3 rgbEnergy, float worldRadius) {
  vec4 clip = uViewProj * vec4(worldPos, 1.0);
  if (clip.w <= 0.05) {
    discardPhoton();
    return;
  }

  float camDist = length(worldPos - uCamPos);
  float idealPx = (2.0 * worldRadius / max(camDist, 0.1)) * (uResolution.y * 0.5 / uTanHalfFov);
  float clampedPx = clamp(idealPx, 1.5, 14.0);
  float areaComp = (idealPx * idealPx) / (clampedPx * clampedPx);

  gl_Position = clip;
  gl_PointSize = clampedPx;
  vColor = rgbEnergy * areaComp;
  vCamDist = camDist;
}

// Splat no Atlas 3D com normalização física exata por área (W/m^2 uniforme em qualquer superfície)
void emitWorldSurfaceSplat(PhotonHit hit, vec3 rgbPower) {
  vec2 uv = vec2(-1.0);
  float worldW = 1.0;
  float worldH = 1.0;
  float atlasW = 0.46;
  float atlasH = 0.46;

  if (hit.surfaceId == SURF_SCREEN) {
    float su = (hit.pos.x + 1.60) / 1.78;
    float sv = (hit.pos.y + 0.80) / 1.35;
    uv = vec2(0.02 + su * 0.46, 0.52 + sv * 0.46);
    worldW = 1.78; worldH = 1.35;
  } else if (hit.surfaceId == SURF_FLOOR) {
    float su = (hit.pos.x + 1.80) / 3.60;
    float sv = (hit.pos.z + 1.40) / 3.20;
    uv = vec2(0.52 + su * 0.46, 0.52 + sv * 0.46);
    worldW = 3.60; worldH = 3.20;
  } else if (hit.surfaceId == SURF_SLIT_PLATE) {
    vec3 rel = hit.pos - SLIT_CENTER;
    float su = (dot(rel, SLIT_TANGENT) + 0.25) / 0.50;
    float sv = (rel.y + 0.44) / 0.88;
    uv = vec2(0.02 + su * 0.46, 0.02 + sv * 0.46);
    worldW = 0.50; worldH = 0.88;
  } else if (hit.surfaceId == SURF_WALL_LEFT) {
    float su = (hit.pos.z + 1.40) / 3.20;
    float sv = (hit.pos.y + 0.80) / 2.20;
    uv = vec2(0.51 + su * 0.14, 0.02 + sv * 0.46);
    worldW = 3.20; worldH = 2.20; atlasW = 0.14;
  } else if (hit.surfaceId == SURF_WALL_BACK) {
    float su = (hit.pos.x + 1.80) / 3.60;
    float sv = (hit.pos.y + 0.80) / 2.20;
    uv = vec2(0.68 + su * 0.14, 0.02 + sv * 0.46);
    worldW = 3.60; worldH = 2.20; atlasW = 0.14;
  } else if (hit.surfaceId == SURF_WALL_RIGHT) {
    float su = (hit.pos.z + 1.40) / 3.20;
    float sv = (hit.pos.y + 0.80) / 2.20;
    uv = vec2(0.85 + su * 0.14, 0.02 + sv * 0.46);
    worldW = 3.20; worldH = 2.20; atlasW = 0.14;
  }

  if (uv.x < 0.0) {
    discardPhoton();
    return;
  }

  float texelW = worldW / (atlasW * ATLAS_SIZE);
  float texelH = worldH / (atlasH * ATLAS_SIZE);
  float texelArea = texelW * texelH;

  float worldR = 0.014;
  float idealPx = (2.0 * worldR) / sqrt(texelArea);
  float clampedPx = clamp(idealPx, 2.0, 22.0);

  // Integral gaussiana exp(-r2*4.2) sobre disco de diâmetro clampedPx = 0.74 * (clampedPx*0.5)^2 texels
  float splatTexels = 0.74 * (clampedPx * 0.5) * (clampedPx * 0.5);
  float splatWorldArea = splatTexels * texelArea;

  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
  gl_PointSize = clampedPx;
  vColor = rgbPower / max(splatWorldArea, 1e-6);
  vCamDist = 0.0;
}

void main() {
  uint idx = uint(aIndex + 0.5);
  // Semente diferente entre passe de superfície (0) e passe de ar (1)
  uint passSalt = uint(uPassType) * 1664525u + 1u;
  uint rng = idx * 747796405u + uint(uFrameSeed) * 2891336453u + passSalt;
  pcgHash(rng);

  float laserLambda = sampleLaserWavelength(rng);
  vec3 laserRGB = wavelengthToLinearRGB(laserLambda);
  float laserGain = (uLaserMode == 3) ? 1.8 : 1.0;

  float rDisk = 0.056 * sqrt(rand(rng));
  float phiDisk = 2.0 * PI * rand(rng);
  vec3 ro = LASER_TIP + SLIT_TANGENT * (rDisk * cos(phiDisk)) + vec3(0.0, rDisk * sin(phiDisk), 0.0);
  vec3 rd = SLIT_AXIS;

  PhotonHit firstHit = traceForward(ro, rd, true);
  if (firstHit.type == HIT_NONE) {
    discardPhoton();
    return;
  }

  // Passe 1: Poeira volumétrica pré-fenda
  if (uPassType == 1 && rand(rng) < 0.28) {
    float airFlux = (18000.0 / float(max(uPhotonCount, 1))) * laserGain;
    float tAir = rand(rng) * firstHit.t;
    emitAirSplat(ro + rd * tAir, laserRGB * (airFlux * 0.55 * firstHit.t), 0.013);
    return;
  }

  // Colisão na parte sólida da plaquinha (ou obturador fechado)
  if (firstHit.type == HIT_SLIT_SOLID) {
    if (uPassType == 1) {
      discardPhoton();
      return;
    }
    float refl = evalSpectrumFromRGB(firstHit.albedo, laserLambda);
    float powerPerPhoton = (1.6 / float(max(uPhotonCount, 1))) * laserGain;
    emitWorldSurfaceSplat(firstHit, laserRGB * (powerPerPhoton * refl * INV_PI * 1.4));
    return;
  }

  // Passou fisicamente pela Fenda 1 ou Fenda 2 -> difrata
  float fluxWeight = 1.0;
  if (firstHit.type == HIT_SLIT_OPEN) {
    float sinTheta = clamp((rand(rng) - 0.5) * 0.90, -0.45, 0.45);
    float cosTheta = sqrt(max(0.0, 1.0 - sinTheta * sinTheta));
    float waveWeight = evalOpenSlitsWaveWeight(sinTheta, laserLambda);

    float dy = (rand(rng) - 0.5) * 0.035;
    ro = firstHit.pos + SLIT_AXIS * 0.002;
    rd = normalize(SLIT_AXIS * cosTheta + SLIT_TANGENT * sinTheta + vec3(0.0, dy, 0.0));
    fluxWeight = waveWeight * 2.2;
  } else {
    discardPhoton();
    return;
  }

  // Propaga após as fendas
  for (int bounce = 0; bounce < 4; bounce++) {
    PhotonHit hit = traceForward(ro, rd, false);
    if (hit.type == HIT_NONE) {
      discardPhoton();
      return;
    }

    if (uPassType == 1) {
      if (bounce == 0) {
        float airFlux = (18000.0 / float(max(uPhotonCount, 1))) * laserGain * fluxWeight;
        float maxLen = min(hit.t, 3.2);
        float tAir = rand(rng) * maxLen;
        emitAirSplat(ro + rd * tAir, laserRGB * (airFlux * 0.16 * maxLen), 0.018);
      } else {
        discardPhoton();
      }
      return;
    }

    if (hit.type == HIT_DIFFUSE) {
      float refl = evalSpectrumFromRGB(hit.albedo, laserLambda);
      float powerPerPhoton = (6.2 / float(max(uPhotonCount, 1))) * laserGain * fluxWeight;
      emitWorldSurfaceSplat(hit, laserRGB * (powerPerPhoton * refl * INV_PI));
      return;
    }

    if (hit.type == HIT_METAL) {
      ro = hit.pos + hit.normal * EPS;
      rd = reflect(rd, hit.normal);
      fluxWeight *= 0.80;
    } else if (hit.type == HIT_GLASS) {
      float lamUm = laserLambda * 0.001;
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
      fluxWeight *= 0.96;
    }
  }

  discardPhoton();
}