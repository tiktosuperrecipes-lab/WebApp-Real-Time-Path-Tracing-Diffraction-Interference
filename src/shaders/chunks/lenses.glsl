const int LENS_COUNT = 4;
const float LENS_R = 0.21;
const float LENS_RIM_R = 0.228;

uniform vec3 uLensPos[4];
uniform float uLensYaw[4];
uniform int uSelectedLens;

vec3 getLensPosSafe(int i) {
  bool initialized = (uLensPos[0].y < -0.01 || uLensPos[1].y < -0.01);
  if (initialized) return uLensPos[i];
  if (i == 0) return vec3(1.42, -0.36, -0.90);
  if (i == 1) return vec3(1.42, -0.36, -0.30);
  if (i == 2) return vec3(1.42, -0.36,  0.30);
  return vec3(1.42, -0.36,  0.90);
}

float getLensYawSafe(int i) {
  bool initialized = (uLensPos[0].y < -0.01 || uLensPos[1].y < -0.01);
  return initialized ? uLensYaw[i] : -0.35;
}

bool solveSphereInterval(vec3 ro, vec3 rd, vec3 center, float r, out float t0, out float t1, out vec3 n0, out vec3 n1) {
  vec3 oc = ro - center;
  float b = dot(oc, rd);
  float c = dot(oc, oc) - r * r;
  float disc = b * b - c;
  if (disc < 0.0) return false;
  float s = sqrt(disc);
  t0 = -b - s;
  t1 = -b + s;
  n0 = (ro + rd * t0 - center) / r;
  n1 = (ro + rd * t1 - center) / r;
  return true;
}

bool solveCyl2DInterval(vec2 ro, vec2 rd, float r, out float t0, out float t1, out vec2 n0, out vec2 n1) {
  float a = dot(rd, rd);
  if (a < 1e-8) {
    if (dot(ro, ro) > r * r) return false;
    t0 = -1e20;
    t1 = 1e20;
    n0 = vec2(0.0);
    n1 = vec2(0.0);
    return true;
  }
  float b = dot(ro, rd);
  float c = dot(ro, ro) - r * r;
  float disc = b * b - a * c;
  if (disc < 0.0) return false;
  float s = sqrt(disc);
  t0 = (-b - s) / a;
  t1 = (-b + s) / a;
  n0 = (ro + rd * t0) / r;
  n1 = (ro + rd * t1) / r;
  return true;
}

bool solveSlabZ(float roZ, float rdZ, float halfThick, out float t0, out float t1, out vec3 n0, out vec3 n1) {
  if (abs(rdZ) < 1e-7) {
    if (abs(roZ) > halfThick) return false;
    t0 = -1e20;
    t1 = 1e20;
    n0 = vec3(0.0);
    n1 = vec3(0.0);
    return true;
  }
  float ta = (-halfThick - roZ) / rdZ;
  float tb = ( halfThick - roZ) / rdZ;
  if (ta < tb) {
    t0 = ta; t1 = tb;
    n0 = vec3(0.0, 0.0, -1.0);
    n1 = vec3(0.0, 0.0,  1.0);
  } else {
    t0 = tb; t1 = ta;
    n0 = vec3(0.0, 0.0,  1.0);
    n1 = vec3(0.0, 0.0, -1.0);
  }
  return true;
}

bool pickIntervalHit(float tEnter, float tExit, vec3 nEnter, vec3 nExit, float tMax, inout float bestT, out vec3 bestN) {
  if (tExit - tEnter <= EPS) return false;
  float t = (tEnter > EPS) ? tEnter : tExit;
  if (t <= EPS || t >= min(tMax, bestT)) return false;
  bestT = t;
  bestN = (tEnter > EPS) ? nEnter : nExit;
  return true;
}

// Subtrai intervalo B=[b0,b1] de A=[a0,a1], gerando ate 2 subintervalos validos
void subtractSphereFromInterval(
  float a0, float a1, vec3 na0, vec3 na1,
  bool hasB, float b0, float b1, vec3 nb0, vec3 nb1,
  out bool hasL, out float l0, out float l1, out vec3 nl0, out vec3 nl1,
  out bool hasR, out float r0, out float r1, out vec3 nr0, out vec3 nr1
) {
  hasL = false; hasR = false;
  if (!hasB || b1 <= a0 || b0 >= a1) {
    hasL = (a1 - a0) > EPS;
    l0 = a0; l1 = a1; nl0 = na0; nl1 = na1;
    return;
  }
  if (b0 > a0 + EPS) {
    hasL = true;
    l0 = a0; l1 = min(a1, b0);
    nl0 = na0; nl1 = -nb0;
  }
  if (b1 < a1 - EPS) {
    hasR = true;
    r0 = max(a0, b1); r1 = a1;
    nr0 = -nb1; nr1 = na1;
  }
}

bool intersectSingleLens(int type, vec3 roL, vec3 rdL, float tMax, out float tHit, out vec3 localN) {
  float tc0, tc1;
  vec2 nc0, nc1;
  if (!solveCyl2DInterval(roL.xy, rdL.xy, LENS_R, tc0, tc1, nc0, nc1)) return false;

  tHit = tMax;
  localN = vec3(0.0);
  bool hit = false;

  if (type == 0) {
    // 0: Biconvexa (convergente)
    const float R = 0.52;
    const float DC = 0.4687;
    float t1a, t1b, t2a, t2b;
    vec3 n1a, n1b, n2a, n2b;
    if (!solveSphereInterval(roL, rdL, vec3(0.0, 0.0,  DC), R, t1a, t1b, n1a, n1b)) return false;
    if (!solveSphereInterval(roL, rdL, vec3(0.0, 0.0, -DC), R, t2a, t2b, n2a, n2b)) return false;

    float tEnter = tc0; vec3 nEnter = vec3(nc0, 0.0);
    if (t1a > tEnter) { tEnter = t1a; nEnter = n1a; }
    if (t2a > tEnter) { tEnter = t2a; nEnter = n2a; }

    float tExit = tc1; vec3 nExit = vec3(nc1, 0.0);
    if (t1b < tExit) { tExit = t1b; nExit = n1b; }
    if (t2b < tExit) { tExit = t2b; nExit = n2b; }

    hit = pickIntervalHit(tEnter, tExit, nEnter, nExit, tMax, tHit, localN);
  } else if (type == 1) {
    // 1: Biconcava (divergente)
    const float R = 0.46;
    const float DC = 0.473;
    const float HALF_EDGE = 0.0637;
    float ts0, ts1;
    vec3 ns0, ns1;
    if (!solveSlabZ(roL.z, rdL.z, HALF_EDGE, ts0, ts1, ns0, ns1)) return false;

    float base0 = max(tc0, ts0);
    vec3 nBase0 = (tc0 > ts0) ? vec3(nc0, 0.0) : ns0;
    float base1 = min(tc1, ts1);
    vec3 nBase1 = (tc1 < ts1) ? vec3(nc1, 0.0) : ns1;
    if (base1 - base0 <= EPS) return false;

    float s1a, s1b, s2a, s2b;
    vec3 n1a, n1b, n2a, n2b;
    bool hasS1 = solveSphereInterval(roL, rdL, vec3(0.0, 0.0, -DC), R, s1a, s1b, n1a, n1b);
    bool hasS2 = solveSphereInterval(roL, rdL, vec3(0.0, 0.0,  DC), R, s2a, s2b, n2a, n2b);

    bool hL, hR;
    float l0, l1, r0, r1;
    vec3 nl0, nl1, nr0, nr1;
    subtractSphereFromInterval(
      base0, base1, nBase0, nBase1,
      hasS1, s1a, s1b, n1a, n1b,
      hL, l0, l1, nl0, nl1,
      hR, r0, r1, nr0, nr1
    );

    for (int k = 0; k < 2; k++) {
      if ((k == 0 && !hL) || (k == 1 && !hR)) continue;
      float seg0 = (k == 0) ? l0 : r0;
      float seg1 = (k == 0) ? l1 : r1;
      vec3 nseg0 = (k == 0) ? nl0 : nr0;
      vec3 nseg1 = (k == 0) ? nl1 : nr1;

      bool hA, hB;
      float a0, a1, b0, b1;
      vec3 na0, na1, nb0, nb1;
      subtractSphereFromInterval(
        seg0, seg1, nseg0, nseg1,
        hasS2, s2a, s2b, n2a, n2b,
        hA, a0, a1, na0, na1,
        hB, b0, b1, nb0, nb1
      );
      if (hA) {
        vec3 candN;
        if (pickIntervalHit(a0, a1, na0, na1, tMax, tHit, candN)) {
          localN = candN; hit = true;
        }
      }
      if (hB) {
        vec3 candN;
        if (pickIntervalHit(b0, b1, nb0, nb1, tMax, tHit, candN)) {
          localN = candN; hit = true;
        }
      }
    }
  } else if (type == 2) {
    // 2: Plano-Convexa (convergente suave)
    const float R = 0.50;
    const float FRONT_Z = -0.015;
    const float C_Z = -0.4038;
    float t1a, t1b;
    vec3 n1a, n1b;
    if (!solveSphereInterval(roL, rdL, vec3(0.0, 0.0, C_Z), R, t1a, t1b, n1a, n1b)) return false;

    float tp0 = -1e20, tp1 = 1e20;
    vec3 np0 = vec3(0.0), np1 = vec3(0.0);
    if (abs(rdL.z) < 1e-7) {
      if (roL.z < FRONT_Z) return false;
    } else {
      float tPlane = (FRONT_Z - roL.z) / rdL.z;
      if (rdL.z > 0.0) { tp0 = tPlane; np0 = vec3(0.0, 0.0, -1.0); }
      else             { tp1 = tPlane; np1 = vec3(0.0, 0.0, -1.0); }
    }

    float tEnter = tc0; vec3 nEnter = vec3(nc0, 0.0);
    if (t1a > tEnter) { tEnter = t1a; nEnter = n1a; }
    if (tp0 > tEnter) { tEnter = tp0; nEnter = np0; }

    float tExit = tc1; vec3 nExit = vec3(nc1, 0.0);
    if (t1b < tExit) { tExit = t1b; nExit = n1b; }
    if (tp1 < tExit) { tExit = tp1; nExit = np1; }

    hit = pickIntervalHit(tEnter, tExit, nEnter, nExit, tMax, tHit, localN);
  } else {
    // 3: Cilindrica Convergente (curvatura horizontal em U)
    const float R = 0.48;
    const float DC = 0.4316;
    float t1a, t1b, t2a, t2b;
    vec2 n1a, n1b, n2a, n2b;
    if (!solveCyl2DInterval(roL.xz - vec2(0.0,  DC), rdL.xz, R, t1a, t1b, n1a, n1b)) return false;
    if (!solveCyl2DInterval(roL.xz - vec2(0.0, -DC), rdL.xz, R, t2a, t2b, n2a, n2b)) return false;

    float tEnter = tc0; vec3 nEnter = vec3(nc0, 0.0);
    if (t1a > tEnter) { tEnter = t1a; nEnter = vec3(n1a.x, 0.0, n1a.y); }
    if (t2a > tEnter) { tEnter = t2a; nEnter = vec3(n2a.x, 0.0, n2a.y); }

    float tExit = tc1; vec3 nExit = vec3(nc1, 0.0);
    if (t1b < tExit) { tExit = t1b; nExit = vec3(n1b.x, 0.0, n1b.y); }
    if (t2b < tExit) { tExit = t2b; nExit = vec3(n2b.x, 0.0, n2b.y); }

    hit = pickIntervalHit(tEnter, tExit, nEnter, nExit, tMax, tHit, localN);
  }

  return hit;
}

// Aro metalico fino (anel de montagem) ao redor da lente
bool intersectLensRim(vec3 roL, vec3 rdL, float halfThick, float tMax, out float tHit, out vec3 localN) {
  float to0, to1; vec2 no0, no1;
  if (!solveCyl2DInterval(roL.xy, rdL.xy, LENS_RIM_R, to0, to1, no0, no1)) return false;

  float ts0, ts1; vec3 ns0, ns1;
  if (!solveSlabZ(roL.z, rdL.z, halfThick, ts0, ts1, ns0, ns1)) return false;

  float base0 = max(to0, ts0);
  vec3 nBase0 = (to0 > ts0) ? vec3(no0, 0.0) : ns0;
  float base1 = min(to1, ts1);
  vec3 nBase1 = (to1 < ts1) ? vec3(no1, 0.0) : ns1;
  if (base1 - base0 <= EPS) return false;

  float ti0, ti1; vec2 ni0, ni1;
  bool hasInner = solveCyl2DInterval(roL.xy, rdL.xy, LENS_R + 0.001, ti0, ti1, ni0, ni1);

  bool hL, hR;
  float l0, l1, r0, r1;
  vec3 nl0, nl1, nr0, nr1;
  subtractSphereFromInterval(
    base0, base1, nBase0, nBase1,
    hasInner, ti0, ti1, vec3(ni0, 0.0), vec3(ni1, 0.0),
    hL, l0, l1, nl0, nl1,
    hR, r0, r1, nr0, nr1
  );

  tHit = tMax;
  localN = vec3(0.0);
  bool hit = false;
  if (hL) {
    vec3 candN;
    if (pickIntervalHit(l0, l1, nl0, nl1, tMax, tHit, candN)) {
      localN = candN; hit = true;
    }
  }
  if (hR) {
    vec3 candN;
    if (pickIntervalHit(r0, r1, nr0, nr1, tMax, tHit, candN)) {
      localN = candN; hit = true;
    }
  }
  return hit;
}

bool intersectAllLenses(
  vec3 ro,
  vec3 rd,
  float tMax,
  bool includeHardware,
  out float bestT,
  out vec3 bestOutwardN,
  out int hitKind,
  out int hitLensIdx
) {
  bestT = tMax;
  hitKind = 0; // 1 = vidro, 2 = aro, 3 = pedestal
  hitLensIdx = -1;
  bool anyHit = false;

  for (int i = 0; i < LENS_COUNT; i++) {
    vec3 pos = getLensPosSafe(i);
    float yaw = getLensYawSafe(i);
    float cY = cos(yaw);
    float sY = sin(yaw);
    vec3 U = vec3(cY, 0.0, -sY);
    vec3 A = vec3(sY, 0.0,  cY);

    vec3 oc = ro - pos;
    vec3 roL = vec3(dot(oc, U), oc.y, dot(oc, A));
    vec3 rdL = vec3(dot(rd, U), rd.y, dot(rd, A));

    float tLens;
    vec3 nLensL;
    if (intersectSingleLens(i, roL, rdL, bestT, tLens, nLensL)) {
      bestT = tLens;
      bestOutwardN = U * nLensL.x + vec3(0.0, nLensL.y, 0.0) + A * nLensL.z;
      hitKind = 1;
      hitLensIdx = i;
      anyHit = true;
    }

    if (includeHardware) {
      float rimHalf = (i == 1) ? 0.0637 : 0.022;
      float tRim;
      vec3 nRimL;
      if (intersectLensRim(roL, rdL, rimHalf, bestT, tRim, nRimL)) {
        bestT = tRim;
        bestOutwardN = U * nRimL.x + vec3(0.0, nRimL.y, 0.0) + A * nRimL.z;
        hitKind = 2;
        hitLensIdx = i;
        anyHit = true;
      }

      float topY = pos.y - LENS_R - 0.014;
      if (topY > -0.79) {
        float tPost;
        vec3 nPost;
        bool isCap;
        if (intersectCylinder(ro, rd, vec3(pos.x, -0.80, pos.z), vec3(pos.x, topY, pos.z), 0.018, bestT, tPost, nPost, isCap)) {
          bestT = tPost;
          bestOutwardN = nPost;
          hitKind = 3;
          hitLensIdx = i;
          anyHit = true;
        }
      }
    }
  }

  return anyHit;
}