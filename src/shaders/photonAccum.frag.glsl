precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 vUv;
out vec4 fragColor;

uniform sampler2D uPrevPhotonTex;
uniform sampler2D uCurrPhotonTex;
uniform int uPhotonFrame;

void main() {
  ivec2 pix = ivec2(gl_FragCoord.xy);
  vec3 curr = texelFetch(uCurrPhotonTex, pix, 0).rgb;

  if (uPhotonFrame == 0) {
    fragColor = vec4(curr, 1.0);
  } else {
    vec3 prev = texelFetch(uPrevPhotonTex, pix, 0).rgb;
    float w = 1.0 / float(uPhotonFrame + 1);
    fragColor = vec4(mix(prev, curr, w), 1.0);
  }
}