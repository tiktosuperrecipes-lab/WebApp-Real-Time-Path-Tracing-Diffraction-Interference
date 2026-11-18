bool intersectSphere(
  vec3 ro,
  vec3 rd,
  vec3 center,
  float radius,
  float tMax,
  out float tHit,
  out vec3 outwardNormal
) {
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