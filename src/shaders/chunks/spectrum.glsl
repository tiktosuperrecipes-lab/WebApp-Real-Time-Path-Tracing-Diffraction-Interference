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
  // Fora do visivel [380, 720] nm: representacao em falsa cor de sensor UV / IR
  if (lambda < 380.0) {
    float t = clamp((380.0 - lambda) / 160.0, 0.0, 1.0);
    vec3 edgeViolet = max(XYZ_TO_SRGB * (wavelengthToXYZ(385.0) * vec3(3.028, 3.179, 3.465)), vec3(0.0));
    vec3 uvFalse = vec3(0.55, 0.14, 1.10);
    return mix(edgeViolet, uvFalse, smoothstep(0.0, 0.35, t));
  }
  if (lambda > 720.0) {
    float t = clamp((lambda - 720.0) / 390.0, 0.0, 1.0);
    vec3 edgeRed = max(XYZ_TO_SRGB * (wavelengthToXYZ(695.0) * vec3(3.028, 3.179, 3.465)), vec3(0.0));
    vec3 irFalse = vec3(0.85, 0.09, 0.14);
    return mix(edgeRed, irFalse, smoothstep(0.0, 0.30, t));
  }

  vec3 xyz = wavelengthToXYZ(lambda) * vec3(3.028, 3.179, 3.465);
  return XYZ_TO_SRGB * xyz;
}

float evalSpectrumFromRGB(vec3 rgb, float lambda) {
  float lam = clamp(lambda, 405.0, 680.0);
  float b = exp(-0.5 * pow((lam - 450.0) / 32.0, 2.0));
  float g = exp(-0.5 * pow((lam - 540.0) / 35.0, 2.0));
  float r = exp(-0.5 * pow((lam - 625.0) / 38.0, 2.0));
  return dot(rgb, vec3(r, g, b)) / (r + g + b + 1e-5);
}