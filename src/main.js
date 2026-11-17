import './style.css';
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

import quadVert from './shaders/quad.vert.glsl?raw';
import cornellFrag from './shaders/pathTracer.frag.glsl?raw';
import diffractionFrag from './shaders/diffraction.frag.glsl?raw';
import photonVert from './shaders/photon.vert.glsl?raw';
import photonFrag from './shaders/photon.frag.glsl?raw';
import photonAccumFrag from './shaders/photonAccum.frag.glsl?raw';
import denoiseFrag from './shaders/denoise.frag.glsl?raw';
import displayFrag from './shaders/display.frag.glsl?raw';

const canvas = document.getElementById('gl-canvas');
const statsEl = document.getElementById('stats');
const toggleSceneBtn = document.getElementById('toggle-scene');
const toggleSimBtn = document.getElementById('toggle-sim');
const toggleLaserBtn = document.getElementById('toggle-laser');
const toggleSlitBtn = document.getElementById('toggle-slit');
const toggleDenoiseBtn = document.getElementById('toggle-denoise');

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

const fullSize = new THREE.Vector2();
renderer.getDrawingBufferSize(fullSize);

let renderScale = 1.0;
const traceSize = new THREE.Vector2(
  Math.max(1, Math.floor(fullSize.x * renderScale)),
  Math.max(1, Math.floor(fullSize.y * renderScale))
);

function createAccumMRT(width, height) {
  return new THREE.WebGLRenderTarget(width, height, {
    count: 2,
    type: accumType,
    format: THREE.RGBAFormat,
    minFilter: THREE.NearestFilter,
    magFilter: THREE.NearestFilter,
    wrapS: THREE.ClampToEdgeWrapping,
    wrapT: THREE.ClampToEdgeWrapping,
    depthBuffer: false,
    stencilBuffer: false,
    generateMipmaps: false
  });
}

function createHalfTarget(width, height, filter = THREE.LinearFilter) {
  return new THREE.WebGLRenderTarget(width, height, {
    type: THREE.HalfFloatType,
    format: THREE.RGBAFormat,
    minFilter: filter,
    magFilter: filter,
    wrapS: THREE.ClampToEdgeWrapping,
    wrapT: THREE.ClampToEdgeWrapping,
    depthBuffer: false,
    stencilBuffer: false,
    generateMipmaps: false
  });
}

let readAccum = createAccumMRT(traceSize.x, traceSize.y);
let writeAccum = createAccumMRT(traceSize.x, traceSize.y);

const denoiseA = createHalfTarget(traceSize.x, traceSize.y, THREE.LinearFilter);
const denoiseB = createHalfTarget(traceSize.x, traceSize.y, THREE.LinearFilter);

// Targets em Screen-Space para poeira volumétrica do laser no ar
const airFrameTarget = createHalfTarget(traceSize.x, traceSize.y, THREE.NearestFilter);
let readAirPhoton = createHalfTarget(traceSize.x, traceSize.y, THREE.LinearFilter);
let writeAirPhoton = createHalfTarget(traceSize.x, traceSize.y, THREE.LinearFilter);

// Targets fixos em World-Space (Atlas 1024x1024) para superfícies (NÃO reseta ao mover a câmera!)
const WORLD_ATLAS_SIZE = 1024;
const worldPhotonFrameTarget = createHalfTarget(WORLD_ATLAS_SIZE, WORLD_ATLAS_SIZE, THREE.NearestFilter);
let readWorldPhoton = createHalfTarget(WORLD_ATLAS_SIZE, WORLD_ATLAS_SIZE, THREE.LinearFilter);
let writeWorldPhoton = createHalfTarget(WORLD_ATLAS_SIZE, WORLD_ATLAS_SIZE, THREE.LinearFilter);

const blackTex = new THREE.DataTexture(new Uint8Array([0, 0, 0, 255]), 1, 1, THREE.RGBAFormat);
blackTex.needsUpdate = true;

const SCENE_PRESETS = [
  {
    name: 'Cornell Box',
    frag: cornellFrag,
    camPos: new THREE.Vector3(0.0, 0.05, 3.85),
    target: new THREE.Vector3(0.0, -0.05, 0.0),
    noiseScale: 1.0,
    exposure: 1.0
  },
  {
    name: 'Difração Laser',
    frag: diffractionFrag,
    camPos: new THREE.Vector3(0.45, 0.50, 3.05),
    target: new THREE.Vector3(-0.32, -0.36, -0.35),
    noiseScale: 1.35,
    exposure: 1.15
  }
];

const LASER_MODES = [
  { label: 'Verde 532nm', color: '#bbf7d0', border: 'rgba(74, 222, 128, 0.5)', bg: 'rgba(34, 197, 94, 0.2)' },
  { label: 'Vermelho 650nm', color: '#fecaca', border: 'rgba(248, 113, 113, 0.5)', bg: 'rgba(239, 68, 68, 0.2)' },
  { label: 'Violeta 405nm', color: '#ddd6fe', border: 'rgba(167, 139, 250, 0.5)', bg: 'rgba(139, 92, 246, 0.2)' },
  { label: 'Branco Espectral', color: '#f3f4f6', border: 'rgba(229, 231, 235, 0.5)', bg: 'rgba(255, 255, 255, 0.16)' }
];

const sceneCamera = new THREE.PerspectiveCamera(
  42,
  window.innerWidth / window.innerHeight,
  0.1,
  100
);

const controls = new OrbitControls(sceneCamera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.minDistance = 0.8;
controls.maxDistance = 8.5;

const quadCamera = new THREE.Camera();
const quadGeometry = new THREE.PlaneGeometry(2, 2);

function createPathTracerMaterial(fragmentShader, extraUniforms = {}) {
  return new THREE.RawShaderMaterial({
    glslVersion: THREE.GLSL3,
    vertexShader: quadVert,
    fragmentShader,
    depthTest: false,
    depthWrite: false,
    uniforms: {
      uAccumTexture: { value: null },
      uResolution: { value: traceSize.clone() },
      uSampleCount: { value: 0 },
      uSamplesPerFrame: { value: 1 },
      uCamPos: { value: new THREE.Vector3() },
      uCamMatrix: { value: new THREE.Matrix4() },
      uTanHalfFov: { value: Math.tan(THREE.MathUtils.degToRad(sceneCamera.fov * 0.5)) },
      uAspect: { value: sceneCamera.aspect },
      ...extraUniforms
    }
  });
}

const cachedSceneMaterials = [createPathTracerMaterial(SCENE_PRESETS[0].frag), null];

const PHOTON_COUNT = 131072;
const photonIndices = new Float32Array(PHOTON_COUNT);
for (let i = 0; i < PHOTON_COUNT; i++) photonIndices[i] = i;

const photonGeometry = new THREE.BufferGeometry();
photonGeometry.setAttribute('aIndex', new THREE.BufferAttribute(photonIndices, 1));
photonGeometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(PHOTON_COUNT * 3), 3));
photonGeometry.boundingSphere = new THREE.Sphere(new THREE.Vector3(), 100);

const photonMaterial = new THREE.RawShaderMaterial({
  glslVersion: THREE.GLSL3,
  vertexShader: photonVert,
  fragmentShader: photonFrag,
  depthTest: false,
  depthWrite: false,
  transparent: true,
  blending: THREE.AdditiveBlending,
  uniforms: {
    uViewProj: { value: new THREE.Matrix4() },
    uCamPos: { value: new THREE.Vector3() },
    uResolution: { value: traceSize.clone() },
    uTanHalfFov: { value: Math.tan(THREE.MathUtils.degToRad(sceneCamera.fov * 0.5)) },
    uFrameSeed: { value: 1 },
    uLaserMode: { value: 0 },
    uSlit1Blocked: { value: 0 },
    uPhotonCount: { value: PHOTON_COUNT },
    uPassType: { value: 0 },
    uGBufferTex: { value: blackTex }
  }
});

const photonPoints = new THREE.Points(photonGeometry, photonMaterial);
photonPoints.frustumCulled = false;
const photonScene = new THREE.Scene();
photonScene.add(photonPoints);

const photonAccumMaterial = new THREE.RawShaderMaterial({
  glslVersion: THREE.GLSL3,
  vertexShader: quadVert,
  fragmentShader: photonAccumFrag,
  depthTest: false,
  depthWrite: false,
  uniforms: {
    uPrevPhotonTex: { value: null },
    uCurrPhotonTex: { value: null },
    uPhotonFrame: { value: 0 }
  }
});

const photonAccumScene = new THREE.Scene();
photonAccumScene.add(new THREE.Mesh(quadGeometry, photonAccumMaterial));

const denoiseMaterial = new THREE.RawShaderMaterial({
  glslVersion: THREE.GLSL3,
  vertexShader: quadVert,
  fragmentShader: denoiseFrag,
  depthTest: false,
  depthWrite: false,
  uniforms: {
    uColorTex: { value: null },
    uExtraTex: { value: blackTex },
    uGBufferTex: { value: null },
    uTexSize: { value: new THREE.Vector2(traceSize.x, traceSize.y) },
    uPassIndex: { value: 0 },
    uStepSize: { value: 1 },
    uSampleCount: { value: 1 },
    uHasExtraTex: { value: 0 },
    uNoiseScale: { value: 1.0 }
  }
});

const displayMaterial = new THREE.RawShaderMaterial({
  glslVersion: THREE.GLSL3,
  vertexShader: quadVert,
  fragmentShader: displayFrag,
  depthTest: false,
  depthWrite: false,
  uniforms: {
    uInputTexture: { value: null },
    uExtraTex: { value: blackTex },
    uHasExtraTex: { value: 0 },
    uExposure: { value: 1.0 }
  }
});

const ptMesh = new THREE.Mesh(quadGeometry, cachedSceneMaterials[0]);
const ptScene = new THREE.Scene();
ptScene.add(ptMesh);

const denoiseScene = new THREE.Scene();
denoiseScene.add(new THREE.Mesh(quadGeometry, denoiseMaterial));

const displayScene = new THREE.Scene();
displayScene.add(new THREE.Mesh(quadGeometry, displayMaterial));

const MAX_SPP_PER_FRAME = 64;

let activeSceneId = 0;
let laserSimMode = 0; // 0 = Híbrido, 1 = Fótons Reais
let laserMode = 0;
let slit1Blocked = 0;
let sampleCount = 0;
let airPhotonFrameCount = 0;
let worldPhotonFrameCount = 0;
let frameSeed = 1;
let samplesPerFrame = 1;
let denoiseEnabled = true;
let isMoving = false;
let suppressMoveScale = false;
let lastMoveTime = 0;
let prevFrameTime = performance.now();
let smoothedFrameMs = 16.6;
let baselineVsyncMs = 16.67;
let vsyncSampleFrames = 0;
let hitVsyncCeiling = false;
let sppAdjustCooldown = 0;
let lastGpuMs = null;

const viewProjMatrix = new THREE.Matrix4();
const pendingQueries = [];

function resetCameraAccumulation() {
  sampleCount = 0;
  airPhotonFrameCount = 0;
}

function resetWorldPhotons() {
  worldPhotonFrameCount = 0;
}

function resetAutoSpp() {
  samplesPerFrame = 1;
  sppAdjustCooldown = 3;
  hitVsyncCeiling = false;
  lastGpuMs = null;
}

function resizeScreenTargets(w, h) {
  readAccum.setSize(w, h);
  writeAccum.setSize(w, h);
  denoiseA.setSize(w, h);
  denoiseB.setSize(w, h);
  airFrameTarget.setSize(w, h);
  readAirPhoton.setSize(w, h);
  writeAirPhoton.setSize(w, h);
}

function updateTraceResolution(newScale) {
  if (renderScale === newScale) return;
  renderScale = newScale;

  traceSize.set(
    Math.max(1, Math.floor(fullSize.x * renderScale)),
    Math.max(1, Math.floor(fullSize.y * renderScale))
  );

  resizeScreenTargets(traceSize.x, traceSize.y);

  for (const mat of cachedSceneMaterials) {
    if (mat) mat.uniforms.uResolution.value.copy(traceSize);
  }
  photonMaterial.uniforms.uResolution.value.copy(traceSize);
  denoiseMaterial.uniforms.uTexSize.value.set(traceSize.x, traceSize.y);
  resetCameraAccumulation();
}

function updateSimModeUI() {
  const isReal = laserSimMode === 1;
  toggleSimBtn.textContent = `Feixe: ${isReal ? 'Fótons Reais' : 'Híbrido'} (F)`;
  toggleSimBtn.classList.toggle('real', isReal);

  const mat = cachedSceneMaterials[1];
  if (mat) mat.uniforms.uLaserSimMode.value = laserSimMode;
}

function updateLaserUI() {
  const m = LASER_MODES[laserMode];
  toggleLaserBtn.textContent = `Laser: ${m.label} (L)`;
  toggleLaserBtn.style.color = m.color;
  toggleLaserBtn.style.borderColor = m.border;
  toggleLaserBtn.style.background = m.bg;

  const mat = cachedSceneMaterials[1];
  if (mat) mat.uniforms.uLaserMode.value = laserMode;
  photonMaterial.uniforms.uLaserMode.value = laserMode;
}

function updateSlitUI() {
  toggleSlitBtn.textContent = `Fenda 1: ${slit1Blocked ? 'Tampada' : 'Aberta'} (B)`;
  toggleSlitBtn.classList.toggle('blocked', slit1Blocked === 1);

  const mat = cachedSceneMaterials[1];
  if (mat) mat.uniforms.uSlit1Blocked.value = slit1Blocked;
  photonMaterial.uniforms.uSlit1Blocked.value = slit1Blocked;
}

function switchScene(nextId) {
  activeSceneId = nextId;
  const preset = SCENE_PRESETS[activeSceneId];

  if (!cachedSceneMaterials[activeSceneId]) {
    const extra = activeSceneId === 1
      ? {
          uWorldPhotonTex: { value: blackTex },
          uLaserMode: { value: laserMode },
          uSlit1Blocked: { value: slit1Blocked },
          uLaserSimMode: { value: laserSimMode }
        }
      : {};
    cachedSceneMaterials[activeSceneId] = createPathTracerMaterial(preset.frag, extra);
  }

  const mat = cachedSceneMaterials[activeSceneId];
  mat.uniforms.uResolution.value.copy(traceSize);
  mat.uniforms.uAspect.value = sceneCamera.aspect;
  mat.uniforms.uTanHalfFov.value = Math.tan(
    THREE.MathUtils.degToRad(sceneCamera.fov * 0.5)
  );

  ptMesh.material = mat;
  denoiseMaterial.uniforms.uNoiseScale.value = preset.noiseScale;
  displayMaterial.uniforms.uExposure.value = preset.exposure;

  const isDiff = activeSceneId === 1;
  toggleSimBtn.hidden = !isDiff || !hasFloatBlend;
  toggleLaserBtn.hidden = !isDiff;
  toggleSlitBtn.hidden = !isDiff;
  if (isDiff) {
    updateSimModeUI();
    updateLaserUI();
    updateSlitUI();
  }

  suppressMoveScale = true;
  sceneCamera.position.copy(preset.camPos);
  controls.target.copy(preset.target);
  controls.update();
  suppressMoveScale = false;

  isMoving = false;
  resetAutoSpp();
  updateTraceResolution(1.0);
  resetCameraAccumulation();

  toggleSceneBtn.textContent = `Cena: ${preset.name} (S)`;
}

function setDenoise(enabled) {
  denoiseEnabled = enabled;
  toggleDenoiseBtn.textContent = `Denoise: ${enabled ? 'ON' : 'OFF'} (D)`;
  toggleDenoiseBtn.classList.toggle('off', !enabled);
}

function toggleForwardMode() {
  if (activeSceneId !== 1 || !hasFloatBlend) return;
  laserSimMode = laserSimMode === 0 ? 1 : 0;
  updateSimModeUI();
  resetWorldPhotons();
  resetCameraAccumulation();
}

toggleSceneBtn.addEventListener('click', () => {
  switchScene((activeSceneId + 1) % SCENE_PRESETS.length);
});

toggleSimBtn.addEventListener('click', toggleForwardMode);

toggleLaserBtn.addEventListener('click', () => {
  if (activeSceneId !== 1) return;
  laserMode = (laserMode + 1) % LASER_MODES.length;
  updateLaserUI();
  resetWorldPhotons();
  resetCameraAccumulation();
});

toggleSlitBtn.addEventListener('click', () => {
  if (activeSceneId !== 1) return;
  slit1Blocked = slit1Blocked ? 0 : 1;
  updateSlitUI();
  resetWorldPhotons();
  resetCameraAccumulation();
});

toggleDenoiseBtn.addEventListener('click', () => setDenoise(!denoiseEnabled));

window.addEventListener('keydown', (e) => {
  const k = e.key.toLowerCase();
  if (k === 'd') {
    setDenoise(!denoiseEnabled);
  } else if (k === 's') {
    switchScene((activeSceneId + 1) % SCENE_PRESETS.length);
  } else if (k === 'f') {
    toggleForwardMode();
  } else if (k === 'l' && activeSceneId === 1) {
    laserMode = (laserMode + 1) % LASER_MODES.length;
    updateLaserUI();
    resetWorldPhotons();
    resetCameraAccumulation();
  } else if (k === 'b' && activeSceneId === 1) {
    slit1Blocked = slit1Blocked ? 0 : 1;
    updateSlitUI();
    resetWorldPhotons();
    resetCameraAccumulation();
  }
});

controls.addEventListener('change', () => {
  if (suppressMoveScale) return;
  isMoving = true;
  lastMoveTime = performance.now();
  samplesPerFrame = 1;
  updateTraceResolution(0.5);
  resetCameraAccumulation();
});

function handleResize() {
  const width = window.innerWidth;
  const height = window.innerHeight;

  sceneCamera.aspect = width / height;
  sceneCamera.updateProjectionMatrix();

  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2.0));
  renderer.setSize(width, height);
  renderer.getDrawingBufferSize(fullSize);

  traceSize.set(
    Math.max(1, Math.floor(fullSize.x * renderScale)),
    Math.max(1, Math.floor(fullSize.y * renderScale))
  );

  resizeScreenTargets(traceSize.x, traceSize.y);

  const tanHalfFov = Math.tan(THREE.MathUtils.degToRad(sceneCamera.fov * 0.5));
  for (const mat of cachedSceneMaterials) {
    if (mat) {
      mat.uniforms.uResolution.value.copy(traceSize);
      mat.uniforms.uAspect.value = sceneCamera.aspect;
      mat.uniforms.uTanHalfFov.value = tanHalfFov;
    }
  }
  photonMaterial.uniforms.uResolution.value.copy(traceSize);
  photonMaterial.uniforms.uTanHalfFov.value = tanHalfFov;
  denoiseMaterial.uniforms.uTexSize.value.set(traceSize.x, traceSize.y);

  resetAutoSpp();
  resetCameraAccumulation();
}

window.addEventListener('resize', handleResize);

switchScene(0);

const ATROUS_STEPS = [1, 2, 4];

function pollGpuTimer() {
  if (!timerExt || pendingQueries.length === 0) return;

  while (pendingQueries.length > 0) {
    const oldest = pendingQueries[0];
    const available = gl.getQueryParameter(oldest.query, gl.QUERY_RESULT_AVAILABLE);
    if (!available) break;

    const disjoint = gl.getParameter(timerExt.GPU_DISJOINT_EXT);
    if (!disjoint && oldest.sceneId === activeSceneId) {
      const ns = gl.getQueryParameter(oldest.query, gl.QUERY_RESULT);
      const ms = ns / 1e6;
      lastGpuMs = lastGpuMs === null ? ms : lastGpuMs * 0.6 + ms * 0.4;
    }
    gl.deleteQuery(oldest.query);
    pendingQueries.shift();
  }
}

function adjustAutoSpp(dt) {
  if (vsyncSampleFrames < 12 && samplesPerFrame === 1 && dt >= 3.5 && dt <= 35.0) {
    baselineVsyncMs = vsyncSampleFrames === 0 ? dt : Math.min(baselineVsyncMs, dt * 1.02);
    vsyncSampleFrames += 1;
  }

  if (sppAdjustCooldown > 0) {
    sppAdjustCooldown -= 1;
    return;
  }

  const budgetMs = Math.max(4.5, baselineVsyncMs * 0.80);

  if (lastGpuMs !== null) {
    if (lastGpuMs < budgetMs * 0.85 && samplesPerFrame < MAX_SPP_PER_FRAME) {
      const step = Math.max(1, Math.floor(samplesPerFrame * 0.25));
      samplesPerFrame = Math.min(MAX_SPP_PER_FRAME, samplesPerFrame + step);
      sppAdjustCooldown = 3;
    } else if (lastGpuMs > budgetMs * 1.08 && samplesPerFrame > 1) {
      samplesPerFrame = Math.max(1, Math.floor(samplesPerFrame * 0.82));
      sppAdjustCooldown = 3;
    }
  } else {
    if (dt > baselineVsyncMs * 1.18 && samplesPerFrame > 1) {
      samplesPerFrame = Math.max(1, Math.floor(samplesPerFrame * 0.80));
      hitVsyncCeiling = true;
      sppAdjustCooldown = 10;
    } else if (!hitVsyncCeiling && dt <= baselineVsyncMs * 1.12 && samplesPerFrame < MAX_SPP_PER_FRAME) {
      const step = Math.max(1, Math.floor(samplesPerFrame * 0.25));
      samplesPerFrame = Math.min(MAX_SPP_PER_FRAME, samplesPerFrame + step);
      sppAdjustCooldown = 4;
    }
  }
}

function animate(now) {
  requestAnimationFrame(animate);

  const dt = Math.min(Math.max(now - prevFrameTime, 1), 100);
  prevFrameTime = now;
  smoothedFrameMs = smoothedFrameMs * 0.85 + dt * 0.15;

  pollGpuTimer();
  controls.update();
  sceneCamera.updateMatrixWorld();
  sceneCamera.matrixWorldInverse.copy(sceneCamera.matrixWorld).invert();
  viewProjMatrix.multiplyMatrices(sceneCamera.projectionMatrix, sceneCamera.matrixWorldInverse);

  if (isMoving && now - lastMoveTime > 120) {
    isMoving = false;
    resetAutoSpp();
    updateTraceResolution(1.0);
  }

  if (!isMoving) {
    adjustAutoSpp(dt);
  }

  let activeQuery = null;
  if (timerExt && pendingQueries.length < 4) {
    activeQuery = gl.createQuery();
    gl.beginQuery(timerExt.TIME_ELAPSED_EXT, activeQuery);
  }

  const useForwardPhotons = activeSceneId === 1 && laserSimMode === 1 && hasFloatBlend;
  frameSeed = (frameSeed + 1) | 0;

  // 1. Fótons Forward de Superfície -> Atlas 3D (1024x1024, não reseta ao mover a câmera!)
  if (useForwardPhotons) {
    photonMaterial.uniforms.uPassType.value = 0;
    photonMaterial.uniforms.uFrameSeed.value = frameSeed;
    photonMaterial.uniforms.uGBufferTex.value = blackTex;

    renderer.setRenderTarget(worldPhotonFrameTarget);
    renderer.setClearColor(0x000000, 0);
    renderer.clearColor();
    renderer.render(photonScene, quadCamera);

    photonAccumMaterial.uniforms.uPrevPhotonTex.value = readWorldPhoton.texture;
    photonAccumMaterial.uniforms.uCurrPhotonTex.value = worldPhotonFrameTarget.texture;
    photonAccumMaterial.uniforms.uPhotonFrame.value = worldPhotonFrameCount;

    renderer.setRenderTarget(writeWorldPhoton);
    renderer.render(photonAccumScene, quadCamera);

    const tmpW = readWorldPhoton;
    readWorldPhoton = writeWorldPhoton;
    writeWorldPhoton = tmpW;
    worldPhotonFrameCount += 1;
  }

  // 2. Path Tracing (agora enxerga o Atlas 3D em reflexos, refrações e GI!)
  const activeMat = ptMesh.material;
  activeMat.uniforms.uAccumTexture.value = readAccum.textures[0];
  activeMat.uniforms.uSampleCount.value = sampleCount;
  activeMat.uniforms.uSamplesPerFrame.value = samplesPerFrame;
  activeMat.uniforms.uCamPos.value.copy(sceneCamera.position);
  activeMat.uniforms.uCamMatrix.value.copy(sceneCamera.matrixWorld);
  if (activeSceneId === 1) {
    activeMat.uniforms.uWorldPhotonTex.value = useForwardPhotons ? readWorldPhoton.texture : blackTex;
  }

  renderer.setRenderTarget(writeAccum);
  renderer.render(ptScene, quadCamera);

  // 3. Fótons Forward Volumétricos no Ar (Screen-Space com oclusão pelo G-Buffer)
  if (useForwardPhotons) {
    photonMaterial.uniforms.uPassType.value = 1;
    photonMaterial.uniforms.uViewProj.value.copy(viewProjMatrix);
    photonMaterial.uniforms.uCamPos.value.copy(sceneCamera.position);
    photonMaterial.uniforms.uFrameSeed.value = frameSeed;
    photonMaterial.uniforms.uGBufferTex.value = writeAccum.textures[1];

    renderer.setRenderTarget(airFrameTarget);
    renderer.setClearColor(0x000000, 0);
    renderer.clearColor();
    renderer.render(photonScene, quadCamera);

    photonAccumMaterial.uniforms.uPrevPhotonTex.value = readAirPhoton.texture;
    photonAccumMaterial.uniforms.uCurrPhotonTex.value = airFrameTarget.texture;
    photonAccumMaterial.uniforms.uPhotonFrame.value = airPhotonFrameCount;

    renderer.setRenderTarget(writeAirPhoton);
    renderer.render(photonAccumScene, quadCamera);

    const tmpA = readAirPhoton;
    readAirPhoton = writeAirPhoton;
    writeAirPhoton = tmpA;
    airPhotonFrameCount += 1;
  }

  const nextSampleCount = sampleCount + samplesPerFrame;
  let finalHdrTexture = writeAccum.textures[0];

  // 4. Denoiser À-Trous
  if (denoiseEnabled) {
    denoiseMaterial.uniforms.uGBufferTex.value = writeAccum.textures[1];
    denoiseMaterial.uniforms.uSampleCount.value = nextSampleCount;

    let srcTex = writeAccum.textures[0];
    const dstTargets = [denoiseA, denoiseB, denoiseA];

    for (let i = 0; i < ATROUS_STEPS.length; i++) {
      denoiseMaterial.uniforms.uColorTex.value = srcTex;
      denoiseMaterial.uniforms.uPassIndex.value = i;
      denoiseMaterial.uniforms.uStepSize.value = ATROUS_STEPS[i];

      if (i === 0 && useForwardPhotons) {
        denoiseMaterial.uniforms.uExtraTex.value = readAirPhoton.texture;
        denoiseMaterial.uniforms.uHasExtraTex.value = 1;
      } else {
        denoiseMaterial.uniforms.uExtraTex.value = blackTex;
        denoiseMaterial.uniforms.uHasExtraTex.value = 0;
      }

      renderer.setRenderTarget(dstTargets[i]);
      renderer.render(denoiseScene, quadCamera);
      srcTex = dstTargets[i].texture;
    }

    finalHdrTexture = denoiseA.texture;
  }

  // 5. Display final (ACES + sRGB)
  displayMaterial.uniforms.uInputTexture.value = finalHdrTexture;
  if (!denoiseEnabled && useForwardPhotons) {
    displayMaterial.uniforms.uExtraTex.value = readAirPhoton.texture;
    displayMaterial.uniforms.uHasExtraTex.value = 1;
  } else {
    displayMaterial.uniforms.uExtraTex.value = blackTex;
    displayMaterial.uniforms.uHasExtraTex.value = 0;
  }

  renderer.setRenderTarget(null);
  renderer.render(displayScene, quadCamera);

  if (activeQuery) {
    gl.endQuery(timerExt.TIME_ELAPSED_EXT);
    pendingQueries.push({ query: activeQuery, sceneId: activeSceneId });
  }

  const temp = readAccum;
  readAccum = writeAccum;
  writeAccum = temp;

  sampleCount = nextSampleCount;

  const fps = Math.round(1000 / smoothedFrameMs);
  const gpuInfo = lastGpuMs !== null ? ` | GPU: ${lastGpuMs.toFixed(1)}ms` : '';
  const photonInfo = useForwardPhotons ? ` | Atlas: ${worldPhotonFrameCount}f` : '';
  statsEl.textContent =
    `Amostras: ${sampleCount} (+${samplesPerFrame}/frame) | ` +
    `${fps} FPS${gpuInfo}${photonInfo} | ${traceSize.x}x${traceSize.y} (${renderScale}x) | ${bufferLabel}`;
}

requestAnimationFrame(animate);