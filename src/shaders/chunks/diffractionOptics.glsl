float sampleLaserWavelength(float roomLambda, inout uint rng) {
  if (uLaserMode == 0) return 532.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 1) return 650.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 2) return 405.0 + (rand(rng) - 0.5) * 3.0;
  return roomLambda;
}

vec3 sampleOverheadLightRGB(HitInfo hit, inout uint rng) {
  float lx = mix(LIGHT_MIN.x, LIGHT_MAX.x, rand(rng));
  float lz = mix(LIGHT_MIN.z, LIGHT_MAX.z, rand(rng));
  vec3 lightPos = vec3(lx, LIGHT_MIN.y, lz);

  vec3 toLight = lightPos - hit.pos;
  float dist2 = dot(toLight, toLight);
  float dist = sqrt(dist2);
  vec3 L = toLight / dist;

  float cosSurf = dot(hit.normal, L);
  float cosLight = dot(LIGHT_NORMAL, -L);
  if (cosSurf <= 0.0 || cosLight <= 0.0) return vec3(0.0);

  if (traceShadow(hit.pos + hit.normal * EPS, L, dist - EPS * 2.0)) return vec3(0.0);

  float geom = (cosSurf * cosLight) / dist2;
  return (hit.albedo * INV_PI) * LIGHT_EMISSION * geom * LIGHT_AREA;
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
      float u = mix(SLIT1_MIN_U, SLIT1_MAX_U, (float(i) + rand(rng)) * invN);
      vec3 slitPt = SLIT_CENTER + SLIT_TANGENT * u + vec3(0.0, vSlit, 0.0);
      vec3 toSlit = slitPt - shadowStart;
      float dOut = length(toSlit);
      if (!traceShadow(shadowStart, toSlit / dOut, dOut - 0.015)) {
        float dIn = length(slitPt - LASER_TIP) - 0.56;
        float phase = k * ((dIn + dOut) - dRef);
        float amp = ((1.0 + cosAxis) * 0.5) * invN / max(dOut, 0.25);
        phasor += vec2(cos(phase), sin(phase)) * amp;
      }
    }
  }

  for (int i = 0; i < nSubPerSlit; i++) {
    float u = mix(SLIT2_MIN_U, SLIT2_MAX_U, (float(i) + rand(rng)) * invN);
    vec3 slitPt = SLIT_CENTER + SLIT_TANGENT * u + vec3(0.0, vSlit, 0.0);
    vec3 toSlit = slitPt - shadowStart;
    float dOut = length(toSlit);
    if (!traceShadow(shadowStart, toSlit / dOut, dOut - 0.015)) {
      float dIn = length(slitPt - LASER_TIP) - 0.56;
      float phase = k * ((dIn + dOut) - dRef);
      float amp = ((1.0 + cosAxis) * 0.5) * invN / max(dOut, 0.25);
      phasor += vec2(cos(phase), sin(phase)) * amp;
    }
  }

  return dot(phasor, phasor) * verticalBeam * cosSurf;
}

vec3 evalGratingFromLight(
  vec3 hitPos,
  vec3 V,
  vec3 R,
  vec3 T,
  vec3 lightPos,
  vec3 lightNormal,
  float lightArea,
  vec3 lightRadiance,
  bool monochromatic,
  float monoLambda,
  inout uint rng
) {
  vec3 toLight = lightPos - hitPos;
  float dist2 = dot(toLight, toLight);
  float dist = sqrt(dist2);
  vec3 L = toLight / max(dist, 1e-5);

  float cosSurf = L.y;
  float cosLight = dot(lightNormal, -L);
  if (cosSurf <= 0.0 || cosLight <= 0.0) return vec3(0.0);
  if (traceShadow(hitPos + vec3(0.0, EPS, 0.0), L, dist - EPS * 2.0)) return vec3(0.0);

  vec3 Hvec = L + V;
  float u = dot(R, Hvec);
  float v = dot(T, Hvec);
  float vTerm = (v * v) / (0.085 * 0.085);
  float geom = (cosSurf * cosLight) / max(dist2, 1e-4);

  if (monochromatic) {
    float diffracted = 0.0;
    for (int m = -2; m <= 2; m++) {
      if (m == 0) continue;
      float uTarget = float(m) * (monoLambda / GRATING_PITCH_NM);
      float du = u - uTarget;
      float orderWeight = (abs(m) == 1) ? 8.5 : 3.0;
      diffracted += orderWeight * exp(-0.5 * ((du * du) / (0.014 * 0.014) + vTerm));
    }
    return lightRadiance * (diffracted * geom * lightArea);
  }

  vec3 spectralRGB = vec3(0.0);
  for (int w = 0; w < 4; w++) {
    float lam = mix(380.0, 720.0, (float(w) + rand(rng)) * 0.25);
    float diffracted = 0.0;
    for (int m = -2; m <= 2; m++) {
      if (m == 0) continue;
      float uTarget = float(m) * (lam / GRATING_PITCH_NM);
      float du = u - uTarget;
      float orderWeight = (abs(m) == 1) ? 8.5 : 3.0;
      diffracted += orderWeight * exp(-0.5 * ((du * du) / (0.014 * 0.014) + vTerm));
    }
    spectralRGB += max(wavelengthToLinearRGB(lam), vec3(0.0)) * diffracted;
  }
  return lightRadiance * (spectralRGB * (0.25 * geom * lightArea));
}

vec3 sampleGratingDiffractionRGB(HitInfo hit, vec3 V, float laserLambda, inout uint rng) {
  vec2 d = hit.pos.xz - DISC_CENTER.xz;
  float lenD = length(d);
  if (lenD < 1e-5) return vec3(0.0);

  vec3 R = vec3(d.x / lenD, 0.0, d.y / lenD);
  vec3 T = vec3(-R.z, 0.0, R.x);

  vec3 rainbowRGB = vec3(0.0);

  for (int i = 0; i < 2; i++) {
    vec3 ceilPos = vec3(
      mix(LIGHT_MIN.x, LIGHT_MAX.x, (float(i) + rand(rng)) * 0.5),
      LIGHT_MIN.y,
      mix(LIGHT_MIN.z, LIGHT_MAX.z, rand(rng))
    );
    rainbowRGB += evalGratingFromLight(
      hit.pos, V, R, T,
      ceilPos, LIGHT_NORMAL, LIGHT_AREA, vec3(LIGHT_EMISSION),
      false, 550.0, rng
    ) * 0.5;
  }

  vec3 scrPos = vec3(
    mix(-1.55, 0.15, rand(rng)),
    mix(-0.66, -0.06, rand(rng)),
    -1.318
  );
  float scrArea = 1.70 * 0.60;
  float laserGain = (uLaserMode == 3) ? 1.8 : 0.95;
  vec3 scrLaserRad = vec3(0.0);

  if (uLaserSimMode == 0) {
    float h = sampleDoubleSlitHuygens(scrPos, vec3(0.0, 0.0, 1.0), true, laserLambda, 4, rng);
    scrLaserRad = max(wavelengthToLinearRGB(laserLambda), vec3(0.0)) * (0.90 * INV_PI * h * 5.2 * laserGain);
  } else {
    scrLaserRad = sampleScreenPhotonAt(scrPos);
  }

  if (dot(scrLaserRad, vec3(1.0)) > 1e-5) {
    bool mono = (uLaserSimMode == 0) || (uLaserMode != 3);
    rainbowRGB += evalGratingFromLight(
      hit.pos, V, R, T,
      scrPos, vec3(0.0, 0.0, 1.0), scrArea, scrLaserRad,
      mono, laserLambda, rng
    );
  }

  HitInfo sheenHit = hit;
  sheenHit.albedo = vec3(0.04);
  return rainbowRGB + sampleOverheadLightRGB(sheenHit, rng);
}

float evalPreSlitLaserBeam(vec3 ro, vec3 rd, float maxT) {
  vec3 w = ro - LASER_TIP;
  float segLen = length(SLIT_CENTER - LASER_TIP);
  float b = dot(rd, SLIT_AXIS);
  float d = dot(rd, w);
  float e = dot(SLIT_AXIS, w);
  float denom = 1.0 - b * b;

  float tc = clamp((denom < 1e-5) ? e : (e - b * d) / denom, 0.0, segLen);
  float sc = max(0.0, -d + tc * b);
  if (sc >= maxT) return 0.0;

  float dist = length((ro + rd * sc) - (LASER_TIP + SLIT_AXIS * tc));
  float core = exp(-(dist * dist) / (0.011 * 0.011));
  float halo = 0.20 * exp(-(dist * dist) / (0.032 * 0.032));
  return (core + halo) * 0.95 / max(sqrt(max(denom, 0.0)), 0.25);
}

float evalPostSlitVolumetricFan(vec3 ro, vec3 rd, float maxT, float laserLambda, inout uint rng) {
  if (abs(rd.y) < 1e-5 && abs(ro.y - SLIT_CENTER.y) > 0.24) return 0.0;

  float t0 = 0.0;
  float t1 = min(maxT, 6.0);
  if (abs(rd.y) >= 1e-5) {
    float ty0 = (SLIT_CENTER.y - 0.22 - ro.y) / rd.y;
    float ty1 = (SLIT_CENTER.y + 0.22 - ro.y) / rd.y;
    t0 = max(t0, min(ty0, ty1));
    t1 = min(t1, max(ty0, ty1));
  }

  float slabLen = t1 - t0;
  if (slabLen <= 0.005) return 0.0;

  const int VOL_STEPS = 3;
  float stepLen = slabLen / float(VOL_STEPS);
  float sumVol = 0.0;
  for (int i = 0; i < VOL_STEPS; i++) {
    vec3 pVol = ro + rd * (t0 + (float(i) + rand(rng)) * stepLen);
    sumVol += sampleDoubleSlitHuygens(pVol, vec3(0.0), false, laserLambda, 4, rng);
  }
  return (sumVol / float(VOL_STEPS)) * slabLen * 0.14;
}