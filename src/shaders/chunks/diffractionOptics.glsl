uniform float uCustomLaserLambda;

float sampleLaserWavelength(float roomLambda, inout uint rng) {
  if (uLaserMode == 0) return 532.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 1) return 650.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 2) return 405.0 + (rand(rng) - 0.5) * 3.0;
  if (uLaserMode == 3) return roomLambda;
  if (uLaserMode == 4) {
    float base = (rand(rng) < 0.5) ? 650.0 : 405.0;
    return base + (rand(rng) - 0.5) * 3.0;
  }
  if (uLaserMode == 5) {
    float r = rand(rng);
    float base = (r < 0.3333) ? 650.0 : ((r < 0.6667) ? 532.0 : 405.0);
    return base + (rand(rng) - 0.5) * 3.0;
  }
  float customLam = (uCustomLaserLambda > 50.0) ? uCustomLaserLambda : 532.0;
  return customLam + (rand(rng) - 0.5) * 3.0;
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
  vec3 scrLaserRad = sampleScreenPhotonAt(scrPos);

  if (dot(scrLaserRad, vec3(1.0)) > 1e-5) {
    bool mono = (uLaserMode < 3) || (uLaserMode == 6);
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