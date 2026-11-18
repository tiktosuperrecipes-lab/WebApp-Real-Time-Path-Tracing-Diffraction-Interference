import './style.css';
import * as THREE from 'three';

import { createGLContext } from './core/glContext.js';
import { createRenderTargets } from './core/renderTargets.js';
import { createFramePacer } from './core/framePacer.js';
import { createRenderPipeline } from './core/pipeline.js';
import { SCENE_PRESETS, createSceneManager } from './scenes/presets.js';
import { createHudController } from './ui/hudController.js';

const canvas = document.getElementById('gl-canvas');
const statsEl = document.getElementById('stats');
const isCoarsePointer = window.matchMedia('(pointer: coarse)').matches;

const { renderer, gl, hasFloatBlend, timerExt, accumType, bufferLabel } = createGLContext(canvas, statsEl);

const fullSize = new THREE.Vector2();
renderer.getDrawingBufferSize(fullSize);

let renderScale = 1.0;
const traceSize = new THREE.Vector2(
  Math.max(1, Math.floor(fullSize.x * renderScale)),
  Math.max(1, Math.floor(fullSize.y * renderScale))
);

const targets = createRenderTargets(traceSize.x, traceSize.y, accumType, 1024);
const pacer = createFramePacer({ gl, timerExt, initialFps: 60 });

const simState = {
  laserSimMode: 0,
  laserMode: 0,
  slit1Blocked: 0,
  denoiseEnabled: true,
  cleanMotionMode: !isCoarsePointer,
  sampleCount: 0,
  airPhotonFrameCount: 0,
  worldPhotonFrameCount: 0,
  isMoving: false,
  lastMoveTime: 0
};

function resetCameraAccumulation() {
  simState.sampleCount = 0;
  simState.airPhotonFrameCount = 0;
}

function resetWorldPhotons() {
  simState.worldPhotonFrameCount = 0;
}

function setTraceScale(newScale) {
  if (renderScale === newScale) return;
  renderScale = newScale;
  traceSize.set(
    Math.max(1, Math.floor(fullSize.x * renderScale)),
    Math.max(1, Math.floor(fullSize.y * renderScale))
  );
  targets.resizeScreen(traceSize.x, traceSize.y);
  sceneManager.updateTraceResolution(traceSize);
  pipeline.updateResolution(traceSize);
  resetCameraAccumulation();
}

const sceneManager = createSceneManager({
  domElement: renderer.domElement,
  traceSize,
  blackTex: targets.blackTex,
  onCameraChange() {
    if (!simState.isMoving) pacer.prepareMotionSpp(simState.cleanMotionMode);
    simState.isMoving = true;
    simState.lastMoveTime = performance.now();
    setTraceScale(simState.cleanMotionMode ? 1.0 : 0.5);
    resetCameraAccumulation();
  }
});

const pipeline = createRenderPipeline({ renderer, targets, sceneManager, traceSize });

function switchToScene(nextId) {
  const id = nextId === null ? (sceneManager.activeSceneId + 1) % SCENE_PRESETS.length : nextId;
  const { preset, material } = sceneManager.switchScene(id, simState, traceSize);
  pipeline.setActiveScene(material, preset);
  pipeline.syncLaserUniforms(simState);
  hud.syncSceneUI(id);
  hud.syncLaserUI(simState);

  simState.isMoving = false;
  pacer.resetAutoSpp(false, simState.cleanMotionMode);
  setTraceScale(1.0);
  resetCameraAccumulation();
}

const hud = createHudController({
  isCoarsePointer,
  hasFloatBlend,
  initialFpsLimit: 60,
  initialCleanMotion: simState.cleanMotionMode,
  onSelectScene: switchToScene,
  onSelectSimMode(nextSim) {
    if (sceneManager.activeSceneId !== 1 || !hasFloatBlend) return;
    const target = nextSim === null ? (simState.laserSimMode === 0 ? 1 : 0) : nextSim;
    if (target === simState.laserSimMode) return;
    simState.laserSimMode = target;
    pipeline.syncLaserUniforms(simState);
    hud.syncLaserUI(simState);
    resetWorldPhotons();
    resetCameraAccumulation();
  },
  onSelectLaserMode(nextLaser) {
    if (sceneManager.activeSceneId !== 1) return;
    const target = nextLaser === null ? (simState.laserMode + 1) % 4 : nextLaser;
    if (target === simState.laserMode) return;
    simState.laserMode = target;
    pipeline.syncLaserUniforms(simState);
    hud.syncLaserUI(simState);
    resetWorldPhotons();
    resetCameraAccumulation();
  },
  onToggleSlit() {
    if (sceneManager.activeSceneId !== 1) return;
    simState.slit1Blocked = simState.slit1Blocked ? 0 : 1;
    pipeline.syncLaserUniforms(simState);
    hud.syncLaserUI(simState);
    resetWorldPhotons();
    resetCameraAccumulation();
  },
  onToggleDenoise() {
    simState.denoiseEnabled = !simState.denoiseEnabled;
    hud.syncDenoiseUI(simState.denoiseEnabled);
  },
  onToggleCleanMotion() {
    simState.cleanMotionMode = !simState.cleanMotionMode;
    hud.syncCleanMotionUI(simState.cleanMotionMode);
    if (simState.isMoving) {
      if (simState.cleanMotionMode) {
        setTraceScale(1.0);
        pacer.setSamplesPerFrame(pacer.motionSpp);
      } else {
        setTraceScale(0.5);
        pacer.setSamplesPerFrame(1);
      }
      resetCameraAccumulation();
    }
  },
  onChangeFpsLimit(fps) {
    pacer.setFpsLimit(fps);
  },
  onResetCamera() {
    sceneManager.resetCameraView();
    simState.isMoving = false;
    pacer.resetAutoSpp(false, simState.cleanMotionMode);
    setTraceScale(1.0);
    resetCameraAccumulation();
  }
});

function handleResize() {
  const width = window.innerWidth;
  const height = window.innerHeight;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2.0));
  renderer.setSize(width, height);
  renderer.getDrawingBufferSize(fullSize);

  traceSize.set(
    Math.max(1, Math.floor(fullSize.x * renderScale)),
    Math.max(1, Math.floor(fullSize.y * renderScale))
  );
  targets.resizeScreen(traceSize.x, traceSize.y);

  const tanHalfFov = sceneManager.updateProjection(width, height, traceSize);
  pipeline.updateResolution(traceSize, tanHalfFov);
  pacer.resetAutoSpp(simState.isMoving, simState.cleanMotionMode);
  resetCameraAccumulation();
}

window.addEventListener('resize', handleResize);
window.addEventListener('orientationchange', () => setTimeout(handleResize, 120));

switchToScene(0);

function animate(now) {
  requestAnimationFrame(animate);

  const { shouldRender, dt, targetFrameMs } = pacer.tickAndShouldRender(now);
  if (!shouldRender) return;

  pacer.pollGpuTimer(sceneManager.activeSceneId);
  sceneManager.updateCameraMatrices();

  if (simState.isMoving && now - simState.lastMoveTime > 120) {
    simState.isMoving = false;
    pacer.resetAutoSpp(false, simState.cleanMotionMode);
    setTraceScale(1.0);
  }

  pacer.adjustAutoSpp(dt, simState.isMoving, simState.cleanMotionMode, targetFrameMs);

  const useForwardPhotons = sceneManager.activeSceneId === 1 && simState.laserSimMode === 1 && hasFloatBlend;
  const query = pacer.beginGpuQuery();

  pipeline.renderFrame({
    activeSceneId: sceneManager.activeSceneId,
    useForwardPhotons,
    denoiseEnabled: simState.denoiseEnabled,
    sampleCount: simState.sampleCount,
    samplesPerFrame: pacer.samplesPerFrame,
    airPhotonFrameCount: simState.airPhotonFrameCount,
    worldPhotonFrameCount: simState.worldPhotonFrameCount
  });

  pacer.endGpuQuery(query, sceneManager.activeSceneId);

  simState.sampleCount += pacer.samplesPerFrame;
  if (useForwardPhotons) {
    simState.worldPhotonFrameCount += 1;
    simState.airPhotonFrameCount += 1;
  }

  hud.updateStats({
    sampleCount: simState.sampleCount,
    samplesPerFrame: pacer.samplesPerFrame,
    fps: Math.round(1000 / pacer.smoothedFrameMs),
    gpuMs: pacer.lastGpuMs,
    useForwardPhotons,
    worldPhotonFrameCount: simState.worldPhotonFrameCount,
    traceSize,
    renderScale,
    bufferLabel
  });
}

requestAnimationFrame(animate);