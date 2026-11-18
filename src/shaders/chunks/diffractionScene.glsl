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

const vec3 LIGHT_MIN = vec3(0.25, 1.399, -0.15);
const vec3 LIGHT_MAX = vec3(0.69, 1.399, 0.29);
const vec3 LIGHT_NORMAL = vec3(0.0, -1.0, 0.0);
const float LIGHT_EMISSION = 14.0;
const float LIGHT_AREA = 0.44 * 0.44;

const vec3 SLIT_CENTER = vec3(-1.10, -0.36, 0.05);
const vec3 SLIT_AXIS = vec3(0.34394, 0.0, -0.93899);
const vec3 SLIT_TANGENT = vec3(0.93899, 0.0, 0.34394);
const vec3 LASER_PIVOT = SLIT_CENTER - SLIT_AXIS * 0.80;
const float LASER_RADIUS = 0.062;

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

uniform vec3 uLaserDir;
uniform float uLaserBeamRadius;
uniform int uSlitPlateEnabled;

vec3 getLaserDirSafe() {
  return (dot(uLaserDir, uLaserDir) > 0.1) ? normalize(uLaserDir) : SLIT_AXIS;
}

float getLaserBeamRadiusSafe() {
  return (uLaserBeamRadius > 0.001) ? uLaserBeamRadius : 0.056;
}

bool isSlitPlateActive() {
  return (uLaserBeamRadius <= 0.001) || (uSlitPlateEnabled == 1);
}

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

bool intersectSlitPlate(vec3 ro, vec3 rd, float tMax, out float tHit, out vec3 outwardN, out bool isShutter) {
  if (!isSlitPlateActive()) return false;
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
  for (int i = 0; i < LENS_COUNT; i++) {
    if (intersectSphereAny(ro, rd, getLensPosSafe(i), LENS_R, maxDist)) return true;
  }
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

  vec3 lDir = getLaserDirSafe();
  vec3 laserBack = LASER_PIVOT - lDir * 0.25;
  vec3 laserTip = LASER_PIVOT + lDir * 0.24;
  float beamR = getLaserBeamRadiusSafe();

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
  if (intersectCylinder(ro, rd, laserBack, laserTip, LASER_RADIUS, hit.t, t, n, isFrontCap)) {
    anyHit = true;
    vec3 p = ro + rd * t;
    float dTip = length(p - laserTip);
    if (isFrontCap && dTip < max(beamR * 0.55, 0.008)) {
      setHitSurface(hit, t, ro, rd, n, vec3(0.0), 18.0, 0.0, MAT_LASER_LENS, SURF_NONE);
    } else if (isFrontCap && dTip < 0.044) {
      setHitSurface(hit, t, ro, rd, n, vec3(0.85, 0.65, 0.25), 0.0, 0.18, MAT_METAL, SURF_NONE);
    } else {
      setHitSurface(hit, t, ro, rd, n, vec3(0.16, 0.17, 0.20), 0.0, 0.28, MAT_METAL, SURF_NONE);
    }
  }

  if (intersectCylinder(ro, rd, vec3(LASER_PIVOT.x, -0.80, LASER_PIVOT.z), LASER_PIVOT, 0.024, hit.t, t, n, isFrontCap)) {
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

  int lensKind, lensIdx;
  if (intersectAllLenses(ro, rd, hit.t, true, t, n, lensKind, lensIdx)) {
    anyHit = true;
    if (lensKind == 1) {
      setHitSurface(hit, t, ro, rd, n, vec3(0.98), 0.0, 0.0, MAT_GLASS, SURF_NONE);
    } else {
      vec3 rimCol = (lensIdx == uSelectedLens) ? vec3(0.45, 0.72, 0.98) : vec3(0.18, 0.20, 0.24);
      setHitSurface(hit, t, ro, rd, n, rimCol, 0.0, 0.22, MAT_METAL, SURF_NONE);
    }
  }

  return anyHit;
}

vec2 getWorldAtlasUV(int surfaceId, vec3 pos, vec3 normal) {
  if (surfaceId == SURF_SCREEN) {
    return vec2(0.02 + ((pos.x + 1.60) / 1.78) * 0.46, 0.52 + ((pos.y + 0.80) / 1.35) * 0.46);
  } else if (surfaceId == SURF_FLOOR) {
    return vec2(0.52 + ((pos.x + 1.80) / 3.60) * 0.46, 0.52 + ((pos.z + 1.40) / 3.20) * 0.46);
  } else if (surfaceId == SURF_SLIT_PLATE) {
    if (dot(normal, -SLIT_AXIS) < 0.5) return vec2(-1.0);
    vec3 rel = pos - SLIT_CENTER;
    return vec2(0.02 + ((dot(rel, SLIT_TANGENT) + 0.25) / 0.50) * 0.46, 0.02 + ((rel.y + 0.44) / 0.88) * 0.46);
  } else if (surfaceId == SURF_WALL_LEFT) {
    return vec2(0.51 + ((pos.z + 1.40) / 3.20) * 0.14, 0.02 + ((pos.y + 0.80) / 2.20) * 0.46);
  } else if (surfaceId == SURF_WALL_BACK) {
    return vec2(0.68 + ((pos.x + 1.80) / 3.60) * 0.14, 0.02 + ((pos.y + 0.80) / 2.20) * 0.46);
  } else if (surfaceId == SURF_WALL_RIGHT) {
    return vec2(0.85 + ((pos.z + 1.40) / 3.20) * 0.14, 0.02 + ((pos.y + 0.80) / 2.20) * 0.46);
  }
  return vec2(-1.0);
}

vec3 sampleWorldPhotonMap(HitInfo hit) {
  vec2 uv = getWorldAtlasUV(hit.surfaceId, hit.pos, hit.normal);
  if (uv.x < 0.0) return vec3(0.0);
  return texture(uWorldPhotonTex, uv).rgb;
}

vec3 sampleScreenPhotonAt(vec3 pos) {
  vec2 uv = getWorldAtlasUV(SURF_SCREEN, pos, vec3(0.0, 0.0, 1.0));
  return texture(uWorldPhotonTex, uv).rgb;
}