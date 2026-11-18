import * as THREE from 'three';

export function createGLContext(canvas, statsEl) {
  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: false,
    powerPreference: 'high-performance'
  });

  const gl = renderer.getContext();

  if (!renderer.capabilities.isWebGL2) {
    statsEl.textContent = 'Erro: WebGL2 não suportado neste navegador.';
    throw new Error('WebGL2 é obrigatório para este path tracer.');
  }

  const hasFloatBuffer = renderer.extensions.has('EXT_color_buffer_float');
  if (!hasFloatBuffer) {
    renderer.extensions.has('EXT_color_buffer_half_float');
    console.warn('EXT_color_buffer_float indisponível; usando HalfFloatType.');
  }

  const hasFloatBlend = renderer.extensions.has('EXT_float_blend');
  if (!hasFloatBlend) {
    console.warn('EXT_float_blend indisponível; modo Fótons Reais desativado.');
  }

  const timerExt = gl.getExtension('EXT_disjoint_timer_query_webgl2');
  const accumType = hasFloatBuffer ? THREE.FloatType : THREE.HalfFloatType;
  const bufferLabel = hasFloatBuffer ? 'RGBA32F' : 'RGBA16F';

  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2.0));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.toneMapping = THREE.NoToneMapping;

  return {
    renderer,
    gl,
    hasFloatBuffer,
    hasFloatBlend,
    timerExt,
    accumType,
    bufferLabel
  };
}