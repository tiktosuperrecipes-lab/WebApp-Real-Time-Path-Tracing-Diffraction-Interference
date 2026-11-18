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