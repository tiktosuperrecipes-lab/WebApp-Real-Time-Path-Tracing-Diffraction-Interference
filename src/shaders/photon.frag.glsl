precision highp float;
precision highp int;
precision highp sampler2D;

in vec3 vColor;
in float vCamDist;

out vec4 fragColor;

uniform sampler2D uGBufferTex;
uniform int uPassType;

void main() {
  if (any(isnan(vColor)) || any(isinf(vColor))) discard;

  vec2 d = gl_PointCoord * 2.0 - 1.0;
  float r2 = dot(d, d);
  if (r2 > 1.0) discard;

  // Passe 1 (poeira no ar) faz teste de oclusão contra o G-Buffer da câmera
  if (uPassType == 1) {
    ivec2 pix = ivec2(gl_FragCoord.xy);
    float sceneDepth = texelFetch(uGBufferTex, pix, 0).w;
    if (sceneDepth > 0.0 && vCamDist > sceneDepth + 0.025) {
      discard;
    }
  }

  float weight = exp(-r2 * 4.2);
  fragColor = vec4(vColor * weight, 1.0);
}