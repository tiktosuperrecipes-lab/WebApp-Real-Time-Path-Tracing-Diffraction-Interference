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
uniform int uPassType;

out vec3 vColor;
out float vCamDist;

//#include <common>
//#include <rng>
//#include <spectrum>
//#include <intersections>

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

float sampleLaserWavelength(inout uint rng) {
  if (uLaserMode == 0) return 532.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 1) return 650.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 2) return 405.0 + (rand(rng) - 0.5) * 3.0;
  return mix(380.0, 720.0, rand(rng));
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
  float k = (2.0 * PI) / ((laserLambda / 550.0) * 0.0054);
  vec2 phasor = vec2(0.0);
  float invN = 1.0 / 6.0;

  if (uSlit1Blocked == 0) {
    for (int i = 0; i < 6; i++) {
      float phase = -k * mix(SLIT1_MIN_U, SLIT1_MAX_U, (float(i) + 0.5) * invN) * sinTheta;
      phasor += vec2(cos(phase), sin(phase)) * invN;
    }
  }
  for (int i = 0; i < 6; i++) {
    float phase = -k * mix(SLIT2_MIN_U, SLIT2_MAX_U, (float(i) + 0.5) * invN) * sinTheta;
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
  if (clip.w <= 0.05) { discardPhoton(); return; }

  float camDist = length(worldPos - uCamPos);
  float idealPx = (2.0 * worldRadius / max(camDist, 0.1)) * (uResolution.y * 0.5 / uTanHalfFov);
  float clampedPx = clamp(idealPx, 1.5, 14.0);
  float areaComp = (idealPx * idealPx) / (clampedPx * clampedPx);

  gl_Position = clip;
  gl_PointSize = clampedPx;
  vColor = rgbEnergy * areaComp;
  vCamDist = camDist;
}

void emitWorldSurfaceSplat(PhotonHit hit, vec3 rgbPower) {
  vec2 uv = vec2(-1.0);
  float worldW = 1.0, worldH = 1.0, atlasW = 0.46, atlasH = 0.46;

  if (hit.surfaceId == SURF_SCREEN) {
    uv = vec2(0.02 + ((hit.pos.x + 1.60) / 1.78) * 0.46, 0.52 + ((hit.pos.y + 0.80) / 1.35) * 0.46);
    worldW = 1.78; worldH = 1.35;
  } else if (hit.surfaceId == SURF_FLOOR) {
    uv = vec2(0.52 + ((hit.pos.x + 1.80) / 3.60) * 0.46, 0.52 + ((hit.pos.z + 1.40) / 3.20) * 0.46);
    worldW = 3.60; worldH = 3.20;
  } else if (hit.surfaceId == SURF_SLIT_PLATE) {
    vec3 rel = hit.pos - SLIT_CENTER;
    uv = vec2(0.02 + ((dot(rel, SLIT_TANGENT) + 0.25) / 0.50) * 0.46, 0.02 + ((rel.y + 0.44) / 0.88) * 0.46);
    worldW = 0.50; worldH = 0.88;
  } else if (hit.surfaceId == SURF_WALL_LEFT) {
    uv = vec2(0.51 + ((hit.pos.z + 1.40) / 3.20) * 0.14, 0.02 + ((hit.pos.y + 0.80) / 2.20) * 0.46);
    worldW = 3.20; worldH = 2.20; atlasW = 0.14;
  } else if (hit.surfaceId == SURF_WALL_BACK) {
    uv = vec2(0.68 + ((hit.pos.x + 1.80) / 3.60) * 0.14, 0.02 + ((hit.pos.y + 0.80) / 2.20) * 0.46);
    worldW = 3.60; worldH = 2.20; atlasW = 0.14;
  } else if (hit.surfaceId == SURF_WALL_RIGHT) {
    uv = vec2(0.85 + ((hit.pos.z + 1.40) / 3.20) * 0.14, 0.02 + ((hit.pos.y + 0.80) / 2.20) * 0.46);
    worldW = 3.20; worldH = 2.20; atlasW = 0.14;
  }

  if (uv.x < 0.0) { discardPhoton(); return; }

  float texelArea = (worldW / (atlasW * ATLAS_SIZE)) * (worldH / (atlasH * ATLAS_SIZE));
  float clampedPx = clamp((2.0 * 0.014) / sqrt(texelArea), 2.0, 22.0);
  float splatWorldArea = 0.74 * (clampedPx * 0.5) * (clampedPx * 0.5) * texelArea;

  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
  gl_PointSize = clampedPx;
  vColor = rgbPower / max(splatWorldArea, 1e-6);
  vCamDist = 0.0;
}

void main() {
  uint idx = uint(aIndex + 0.5);
  uint rng = idx * 747796405u + uint(uFrameSeed) * 2891336453u + uint(uPassType) * 1664525u + 1u;
  pcgHash(rng);

  float laserLambda = sampleLaserWavelength(rng);
  vec3 laserRGB = max(wavelengthToLinearRGB(laserLambda), vec3(0.0));
  float laserGain = (uLaserMode == 3) ? 1.8 : 1.0;

  float rDisk = 0.056 * sqrt(rand(rng));
  float phiDisk = 2.0 * PI * rand(rng);
  vec3 ro = LASER_TIP + SLIT_TANGENT * (rDisk * cos(phiDisk)) + vec3(0.0, rDisk * sin(phiDisk), 0.0);
  vec3 rd = SLIT_AXIS;

  PhotonHit firstHit = traceForward(ro, rd, true);
  if (firstHit.type == HIT_NONE) { discardPhoton(); return; }

  if (uPassType == 1 && rand(rng) < 0.28) {
    float airFlux = (18000.0 / float(max(uPhotonCount, 1))) * laserGain;
    emitAirSplat(ro + rd * (rand(rng) * firstHit.t), laserRGB * (airFlux * 0.55 * firstHit.t), 0.013);
    return;
  }

  if (firstHit.type == HIT_SLIT_SOLID) {
    if (uPassType == 1) { discardPhoton(); return; }
    float refl = evalSpectrumFromRGB(firstHit.albedo, laserLambda);
    float powerPerPhoton = (1.6 / float(max(uPhotonCount, 1))) * laserGain;
    emitWorldSurfaceSplat(firstHit, laserRGB * (powerPerPhoton * refl * INV_PI * 1.4));
    return;
  }

  if (firstHit.type != HIT_SLIT_OPEN) { discardPhoton(); return; }

  float sinTheta = clamp((rand(rng) - 0.5) * 0.90, -0.45, 0.45);
  float cosTheta = sqrt(max(0.0, 1.0 - sinTheta * sinTheta));
  float fluxWeight = evalOpenSlitsWaveWeight(sinTheta, laserLambda) * 2.2;
  ro = firstHit.pos + SLIT_AXIS * 0.002;
  rd = normalize(SLIT_AXIS * cosTheta + SLIT_TANGENT * sinTheta + vec3(0.0, (rand(rng) - 0.5) * 0.035, 0.0));

  for (int bounce = 0; bounce < 4; bounce++) {
    PhotonHit hit = traceForward(ro, rd, false);
    if (hit.type == HIT_NONE) { discardPhoton(); return; }

    if (uPassType == 1) {
      if (bounce == 0) {
        float airFlux = (18000.0 / float(max(uPhotonCount, 1))) * laserGain * fluxWeight;
        float maxLen = min(hit.t, 3.2);
        emitAirSplat(ro + rd * (rand(rng) * maxLen), laserRGB * (airFlux * 0.16 * maxLen), 0.018);
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
      float cosT = min(dot(-rd, hit.normal), 1.0);
      bool cannotRefract = (eta * eta * max(0.0, 1.0 - cosT * cosT)) > 1.0;

      float r0 = (1.0 - eta) / (1.0 + eta);
      r0 *= r0;
      float fresnel = r0 + (1.0 - r0) * pow(1.0 - cosT, 5.0);

      vec3 nextDir = (cannotRefract || rand(rng) < fresnel) ? reflect(rd, hit.normal) : refract(rd, hit.normal, eta);
      vec3 offsetNormal = (cannotRefract || dot(nextDir, hit.normal) > 0.0) ? hit.normal : -hit.normal;
      ro = hit.pos + offsetNormal * EPS;
      rd = normalize(nextDir);
      fluxWeight *= 0.96;
    }
  }

  discardPhoton();
}