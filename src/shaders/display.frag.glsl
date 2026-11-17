precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 vUv;
out vec4 fragColor;

uniform sampler2D uInputTexture;
uniform sampler2D uExtraTex;
uniform int uHasExtraTex;
uniform float uExposure;

vec3 acesFilmic(vec3 x) {
  const float a = 2.51;
  const float b = 0.03;
  const float c = 2.43;
  const float d = 0.59;
  const float e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 linearToSRGB(vec3 linear) {
  vec3 lo = linear * 12.92;
  vec3 hi = 1.055 * pow(max(linear, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
  return mix(lo, hi, greaterThan(linear, vec3(0.0031308)));
}

void main() {
  vec3 hdrColor = texture(uInputTexture, vUv).rgb;
  if (uHasExtraTex == 1) {
    hdrColor += texture(uExtraTex, vUv).rgb;
  }

  vec3 exposed = max(hdrColor, vec3(0.0)) * uExposure;
  vec3 toneMapped = acesFilmic(exposed);
  vec3 srgb = linearToSRGB(toneMapped);

  fragColor = vec4(srgb, 1.0);
}