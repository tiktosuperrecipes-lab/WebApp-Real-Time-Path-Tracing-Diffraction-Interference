void buildONB(vec3 n, out vec3 tangent, out vec3 bitangent) {
  float s = n.z >= 0.0 ? 1.0 : -1.0;
  float a = -1.0 / (s + n.z);
  float b = n.x * n.y * a;
  tangent = vec3(1.0 + s * n.x * n.x * a, s * b, -s * n.x);
  bitangent = vec3(b, s + n.y * n.y * a, -n.y);
}

vec3 sampleCosineHemisphere(vec3 n, inout uint rng) {
  float u1 = rand(rng);
  float u2 = rand(rng);
  float r = sqrt(u1);
  float phi = 2.0 * PI * u2;
  vec3 t, b;
  buildONB(n, t, b);
  return normalize(t * (r * cos(phi)) + b * (r * sin(phi)) + n * sqrt(max(0.0, 1.0 - u1)));
}

vec3 sampleGGXHalfVector(vec3 n, float alpha, inout uint rng) {
  float u1 = rand(rng);
  float u2 = rand(rng);
  float phi = 2.0 * PI * u1;
  float cosTheta = sqrt((1.0 - u2) / (1.0 + (alpha * alpha - 1.0) * u2));
  float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
  vec3 t, b;
  buildONB(n, t, b);
  return normalize(t * (sinTheta * cos(phi)) + b * (sinTheta * sin(phi)) + n * cosTheta);
}

vec3 fresnelSchlickRGB(float cosTheta, vec3 F0) {
  return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float fresnelSchlickScalar(float cosTheta, float F0) {
  return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float smithG1(float NoX, float alpha2) {
  float NoX2 = NoX * NoX;
  return (2.0 * NoX) / (NoX + sqrt(alpha2 + (1.0 - alpha2) * NoX2));
}