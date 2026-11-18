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
uniform int uSlitPlateEnabled;
uniform int uPhotonCount;
uniform int uPassType;

uniform vec3 uLaserDir;
uniform vec3 uLaserRight;
uniform vec3 uLaserUp;
uniform float uLaserBeamRadius;

out vec3 vColor;
out float vCamDist;

//#include <common>
//#include <rng>
//#include <spectrum>
//#include <intersections>
//#include <lenses>

const float ATLAS_SIZE = 1024.0;

const vec3 SLIT_CENTER = vec3(-1.10, -0.36, 0.05);
const vec3 SLIT_AXIS = vec3(0.34394, 0.0, -0.93899);
const vec3 SLIT_TANGENT = vec3(0.93899, 0.0, 0.34394);
const vec3 LASER_PIVOT = SLIT_CENTER - SLIT_AXIS * 0.80;

const float SLIT1_MIN_U = -0.049;
const float SLIT1_MAX_U = -0.023;
const float SLIT2_MIN_U =  0.023;
const float SLIT2_MAX_U =  0.049;
const float SLIT_HALF_H =  0.15;

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

const int HIT_NONE = 0;
const int HIT_DIFFUSE = 1;
const int HIT_METAL = 2;
const int HIT_GLASS = 3;
const int HIT_SLIT_OPEN = 4;
const int HIT_SLIT_SOLID = 5;
const int HIT_GRATING = 6;

const int SURF_NONE = 0;
const int SURF_SCREEN = 1;
const int SURF_FLOOR = 2;
const int SURF_SLIT_PLATE = 3;
const int SURF_WALL_LEFT = 4;
const int SURF_WALL_BACK = 5;
const int SURF_WALL_RIGHT = 6;

vec3 getLaserDirSafe() {
  return (dot(uLaserDir, uLaserDir) > 0.1) ? normalize(uLaserDir) : SLIT_AXIS;
}
vec3 getLaserRightSafe() {
  return (dot(uLaserRight, uLaserRight) > 0.1) ? normalize(uLaserRight) : SLIT_TANGENT;
}
vec3 getLaserUpSafe() {
  return (dot(uLaserUp, uLaserUp) > 0.1) ? normalize(uLaserUp) : vec3(0.0, 1.0, 0.0);
}
float getLaserBeamRadiusSafe() {
  return (uLaserBeamRadius > 0.001) ? uLaserBeamRadius : 0.056;
}
bool isSlitPlateActive() {
  return (uLaserBeamRadius <= 0.001) || (uSlitPlateEnabled == 1);
}

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

  int lensKind, lensIdx;
  if (intersectAllLenses(ro, rd, hit.t, true, t, n, lensKind, lensIdx)) {
    hit.t = t; hit.pos = ro + rd * t;
    hit.frontFace = dot(rd, n) < 0.0;
    hit.normal = hit.frontFace ? n : -n;
    hit.surfaceId = SURF_NONE;
    if (lensKind == 1) {
      hit.albedo = vec3(0.98);
      hit.type = HIT_GLASS;
    } else {
      hit.albedo = vec3(0.20);
      hit.type = HIT_METAL;
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

  if (rd.y < -1e-6) {
    float tDisc = (DISC_CENTER.y - ro.y) / rd.y;
    if (tDisc > EPS && tDisc < hit.t) {
      vec3 pDisc = ro + rd * tDisc;
      float rDisc = length(pDisc.xz - DISC_CENTER.xz);
      if (rDisc >= DISC_HOLE_R && rDisc <= DISC_OUTER_R) {
        hit.t = tDisc; hit.pos = pDisc;
        hit.normal = vec3(0.0, 1.0, 0.0); hit.frontFace = true;
        hit.surfaceId = SURF_NONE;
        if (rDisc >= DISC_HUB_R && rDisc <= DISC_DATA_R) {
          hit.albedo = vec3(0.92);
          hit.type = HIT_GRATING;
        } else {
          hit.albedo = vec3(0.24);
          hit.type = HIT_METAL;
        }
      }
    }
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
    hit.t = t; hit.pos = ro + rd * t;
    hit.normal = vec3(0.0, 0.0, 1.0); hit.frontFace = true;
    hit.albedo = vec3(0.10); hit.type = HIT_DIFFUSE; hit.surfaceId = SURF_WALL_BACK;
  }
  if (intersectQuadY(ro, rd, 1.4, -1.0, vec2(-1.8, -1.4), vec2(1.8, 1.8), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t;
    hit.normal = vec3(0.0, -1.0, 0.0); hit.frontFace = true;
    hit.albedo = vec3(0.09); hit.type = HIT_DIFFUSE; hit.surfaceId = SURF_NONE;
  }
  if (intersectQuadX(ro, rd, -1.8, 1.0, vec2(-0.8, -1.4), vec2(1.4, 1.8), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t;
    hit.normal = vec3(1.0, 0.0, 0.0); hit.frontFace = true;
    hit.albedo = vec3(0.10); hit.type = HIT_DIFFUSE; hit.surfaceId = SURF_WALL_LEFT;
  }
  if (intersectQuadX(ro, rd, 1.8, -1.0, vec2(-0.8, -1.4), vec2(1.4, 1.8), hit.t, t)) {
    hit.t = t; hit.pos = ro + rd * t;
    hit.normal = vec3(-1.0, 0.0, 0.0); hit.frontFace = true;
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

  vec3 lDir = getLaserDirSafe();
  vec3 lRight = getLaserRightSafe();
  vec3 lUp = getLaserUpSafe();
  float beamR = getLaserBeamRadiusSafe();
  vec3 laserTip = LASER_PIVOT + lDir * 0.24;

  float rDisk = beamR * sqrt(rand(rng));
  float phiDisk = 2.0 * PI * rand(rng);
  vec3 ro = laserTip + lRight * (rDisk * cos(phiDisk)) + lUp * (rDisk * sin(phiDisk));
  vec3 rd = lDir;

  float fluxWeight = 1.0;
  float airAliveProb = 1.0;
  bool inAir = true;
  bool passedSlits = false;
  bool checkSlits = isSlitPlateActive();

  for (int bounce = 0; bounce < 7; bounce++) {
    PhotonHit hit = traceForward(ro, rd, checkSlits);
    if (hit.type == HIT_NONE) { discardPhoton(); return; }

    if (uPassType == 1 && inAir) {
      float segLen = min(hit.t, 3.6);
      float pStop = (bounce == 6) ? 1.0 : ((bounce == 0) ? 0.28 : 0.42);
      if (rand(rng) < pStop) {
        float baseAir = (!passedSlits && bounce == 0) ? 0.52 : 0.18;
        float airFlux = (18000.0 / float(max(uPhotonCount, 1))) * laserGain * fluxWeight;
        float splatR = (!passedSlits && bounce == 0) ? clamp(beamR * 0.35, 0.006, 0.014) : 0.015;
        emitAirSplat(
          ro + rd * (rand(rng) * segLen),
          laserRGB * (airFlux * baseAir * segLen / max(airAliveProb * pStop, 1e-4)),
          splatR
        );
        return;
      }
      airAliveProb *= (1.0 - pStop);
    }

    if (hit.type == HIT_SLIT_SOLID) {
      if (uPassType == 1) { discardPhoton(); return; }
      float refl = evalSpectrumFromRGB(hit.albedo, laserLambda);
      float powerPerPhoton = (1.6 / float(max(uPhotonCount, 1))) * laserGain * fluxWeight;
      emitWorldSurfaceSplat(hit, laserRGB * (powerPerPhoton * refl * INV_PI * 1.4));
      return;
    }

    if (hit.type == HIT_SLIT_OPEN) {
      float sinTheta = clamp((rand(rng) - 0.5) * 0.90, -0.45, 0.45);
      float cosTheta = sqrt(max(0.0, 1.0 - sinTheta * sinTheta));
      fluxWeight *= evalOpenSlitsWaveWeight(sinTheta, laserLambda) * 2.2;

      float forwardSign = (dot(rd, SLIT_AXIS) >= 0.0) ? 1.0 : -1.0;
      ro = hit.pos + SLIT_AXIS * (forwardSign * 0.002);
      rd = normalize(SLIT_AXIS * (forwardSign * cosTheta) + SLIT_TANGENT * sinTheta + vec3(0.0, (rand(rng) - 0.5) * 0.035, 0.0));
      passedSlits = true;
      continue;
    }

    if (hit.type == HIT_DIFFUSE) {
      if (uPassType == 1 || hit.surfaceId == SURF_NONE) { discardPhoton(); return; }
      float refl = evalSpectrumFromRGB(hit.albedo, laserLambda);
      float powerPerPhoton = (6.2 / float(max(uPhotonCount, 1))) * laserGain * fluxWeight;
      emitWorldSurfaceSplat(hit, laserRGB * (powerPerPhoton * refl * INV_PI));
      return;
    }

    if (hit.type == HIT_METAL) {
      ro = hit.pos + hit.normal * EPS;
      rd = reflect(rd, hit.normal);
      fluxWeight *= 0.80;
    } else if (hit.type == HIT_GRATING) {
      vec2 d = hit.pos.xz - DISC_CENTER.xz;
      float lenD = length(d);
      if (lenD < 1e-5) { discardPhoton(); return; }
      vec3 R = vec3(d.x / lenD, 0.0, d.y / lenD);
      vec3 T = vec3(-R.z, 0.0, R.x);

      if (rand(rng) < 0.45) {
        ro = hit.pos + vec3(0.0, EPS, 0.0);
        rd = reflect(rd, hit.normal);
        fluxWeight *= 0.65;
      } else {
        int signM = (rand(rng) < 0.5) ? -1 : 1;
        int magM = (rand(rng) < 0.74) ? 1 : 2;
        float uTarget = float(signM * magM) * (laserLambda / GRATING_PITCH_NM);
        vec3 V_in = -rd;
        float L_R = uTarget - dot(R, V_in);
        float L_T = -dot(T, V_in);
        float horiz2 = L_R * L_R + L_T * L_T;
        if (horiz2 >= 0.995) { discardPhoton(); return; }

        ro = hit.pos + vec3(0.0, EPS, 0.0);
        rd = normalize(R * L_R + T * L_T + vec3(0.0, sqrt(1.0 - horiz2), 0.0));
        fluxWeight *= (magM == 1) ? 0.55 : 0.35;
      }
    } else if (hit.type == HIT_GLASS) {
      float lamUm = laserLambda * 0.001;
      float ior = 1.49 + 0.015 / (lamUm * lamUm);
      float eta = hit.frontFace ? (1.0 / ior) : ior;
      float cosT = min(dot(-rd, hit.normal), 1.0);
      bool cannotRefract = (eta * eta * max(0.0, 1.0 - cosT * cosT)) > 1.0;

      float r0 = (1.0 - eta) / (1.0 + eta);
      r0 *= r0;
      float fresnel = r0 + (1.0 - r0) * pow(1.0 - cosT, 5.0);

      bool doReflect = cannotRefract || (rand(rng) < fresnel);
      vec3 nextDir = doReflect ? reflect(rd, hit.normal) : refract(rd, hit.normal, eta);
      vec3 offsetNormal = (cannotRefract || dot(nextDir, hit.normal) > 0.0) ? hit.normal : -hit.normal;

      if (!doReflect) inAir = !inAir;
      ro = hit.pos + offsetNormal * EPS;
      rd = normalize(nextDir);
      fluxWeight *= 0.96;
    }
  }

  discardPhoton();
}