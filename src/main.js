import './style.css';
import * as THREE from 'three';

import { createGLContext } from './core/glContext.js';
import { createRenderTargets } from './core/renderTargets.js';
import { createFramePacer } from './core/framePacer.js';
import { createRenderPipeline } from './core/pipeline.js';
import { LASER_PIVOT, SCENE_PRESETS, computeLaserBasis, createSceneManager } from './scenes/presets.js';
import { createLensController } from './scenes/lensInteraction.js';
import { createHudController } from './ui/hudController.js';

const canvas = document.getElementById('gl-canvas');
const statsEl = document.getElementById('stats');
const isCoarsePointer = window.matchMedia('(pointer: coarse)').matches;

const { renderer, gl, timerExt, accumType, bufferLabel } = createGLContext(canvas, statsEl);

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
  laserMode: 0,
  customLaserLambda: 532.0,
  slit1Blocked: 0,
  slitPlateEnabled: 1,
  laserBeamRadius: 0.056,
  laserYawDeg: 0,
  laserPitchDeg: 0,
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

function notifyInteractiveMove() {
  if (!simState.isMoving) pacer.prepareMotionSpp(simState.cleanMotionMode);
  simState.isMoving = true;
  simState.lastMoveTime = performance.now();
  setTraceScale(simState.cleanMotionMode ? 1.0 : 0.5);
  resetCameraAccumulation();
}

const sceneManager = createSceneManager({
  domElement: renderer.domElement,
  traceSize,
  blackTex: targets.blackTex,
  onCameraChange: notifyInteractiveMove
});

const pipeline = createRenderPipeline({ renderer, targets, sceneManager, traceSize });

const lensController = createLensController({
  domElement: renderer.domElement,
  camera: sceneManager.camera,
  controls: sceneManager.controls,
  getActiveSceneId: () => sceneManager.activeSceneId,
  onSelectLens() {
    pipeline.syncLensUniforms(lensController);
    hud.syncLensUI(lensController);
  },
  onLensChanged(isDragging) {
    pipeline.syncLensUniforms(lensController);
    resetWorldPhotons();
    if (isDragging) notifyInteractiveMove();
    else resetCameraAccumulation();
  },
  onDragEnd() {
    simState.lastMoveTime = performance.now();
  }
});

function switchToScene(nextId) {
  const id = nextId === null ? (sceneManager.activeSceneId + 1) % SCENE_PRESETS.length : nextId;
  const { preset, material } = sceneManager.switchScene(id, simState, traceSize, lensController);
  pipeline.setActiveScene(material, preset);
  pipeline.syncLaserUniforms(simState);
  pipeline.syncLensUniforms(lensController);
  hud.syncSceneUI(id);
  hud.syncLaserUI(simState);
  hud.syncLensUI(lensController);

  simState.isMoving = false;
  pacer.resetAutoSpp(false, simState.cleanMotionMode);
  setTraceScale(1.0);
  resetCameraAccumulation();
}

const hud = createHudController({
  isCoarsePointer,
  initialFpsLimit: 60,
  initialCleanMotion: simState.cleanMotionMode,
  onSelectScene: switchToScene,
  onSelectLaserMode(nextLaser) {
    if (sceneManager.activeSceneId !== 1) return;
    const target = nextLaser === null ? (simState.laserMode >= 5 ? 0 : simState.laserMode + 1) : nextLaser;
    if (target === simState.laserMode) return;
    simState.laserMode = target;
    if (target === 0) simState.customLaserLambda = 532.0;
    else if (target === 1) simState.customLaserLambda = 650.0;
    else if (target === 2) simState.customLaserLambda = 405.0;
    pipeline.syncLaserUniforms(simState);
    hud.syncLaserUI(simState);
    resetWorldPhotons();
    resetCameraAccumulation();
  },
  onChangeLaserFrequency(nm) {
    if (sceneManager.activeSceneId !== 1) return;
    simState.laserMode = 6;
    simState.customLaserLambda = nm;
    pipeline.syncLaserUniforms(simState);
    hud.syncLaserUI(simState);
    resetWorldPhotons();
    notifyInteractiveMove();
  },
  onChangeLaserBeamRadius(radius) {
    if (sceneManager.activeSceneId !== 1) return;
    simState.laserBeamRadius = radius;
    pipeline.syncLaserUniforms(simState);
    resetWorldPhotons();
    notifyInteractiveMove();
  },
  onChangeLaserYaw(deg) {
    if (sceneManager.activeSceneId !== 1) return;
    simState.laserYawDeg = deg;
    pipeline.syncLaserUniforms(simState);
    resetWorldPhotons();
    notifyInteractiveMove();
  },
  onChangeLaserPitch(deg) {
    if (sceneManager.activeSceneId !== 1) return;
    simState.laserPitchDeg = deg;
    pipeline.syncLaserUniforms(simState);
    resetWorldPhotons();
    notifyInteractiveMove();
  },
  onResetLaser() {
    if (sceneManager.activeSceneId !== 1) return;
    simState.laserBeamRadius = 0.056;
    simState.laserYawDeg = 0;
    simState.laserPitchDeg = 0;
    pipeline.syncLaserUniforms(simState);
    hud.syncLaserUI(simState);
    resetWorldPhotons();
    resetCameraAccumulation();
  },
  onToggleSlitPlate() {
    if (sceneManager.activeSceneId !== 1) return;
    simState.slitPlateEnabled = simState.slitPlateEnabled ? 0 : 1;
    pipeline.syncLaserUniforms(simState);
    hud.syncLaserUI(simState);
    resetWorldPhotons();
    resetCameraAccumulation();
  },
  onToggleSlit() {
    if (sceneManager.activeSceneId !== 1 || simState.slitPlateEnabled === 0) return;
    simState.slit1Blocked = simState.slit1Blocked ? 0 : 1;
    pipeline.syncLaserUniforms(simState);
    hud.syncLaserUI(simState);
    resetWorldPhotons();
    resetCameraAccumulation();
  },
  onSelectLens(idx) {
    if (sceneManager.activeSceneId !== 1) return;
    const next = (idx === lensController.selectedLens) ? -1 : idx;
    lensController.selectLens(next);
  },
  onChangeLensHeight(y) {
    if (sceneManager.activeSceneId !== 1) return;
    lensController.setSelectedHeight(y);
    notifyInteractiveMove();
  },
  onChangeLensYaw(deg) {
    if (sceneManager.activeSceneId !== 1) return;
    lensController.setSelectedYawDeg(deg);
    notifyInteractiveMove();
  },
  onPlaceLensInFront() {
    if (sceneManager.activeSceneId !== 1) return;
    const basis = computeLaserBasis(simState.laserYawDeg, simState.laserPitchDeg);
    lensController.placeSelectedInFrontOfLaser(LASER_PIVOT, basis.dir, 1.15);
    hud.syncLensUI(lensController);
  },
  onResetLens() {
    if (sceneManager.activeSceneId !== 1) return;
    lensController.resetSelectedToCorner();
    hud.syncLensUI(lensController);
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
  },
  onResetScene() {
    sceneManager.resetCameraView();
    if (sceneManager.activeSceneId === 1) {
      simState.laserMode = 0;
      simState.customLaserLambda = 532.0;
      simState.slit1Blocked = 0;
      simState.slitPlateEnabled = 1;
      simState.laserBeamRadius = 0.056;
      simState.laserYawDeg = 0;
      simState.laserPitchDeg = 0;
      lensController.resetAllLenses();
      pipeline.syncLaserUniforms(simState);
      pipeline.syncLensUniforms(lensController);
      hud.syncLaserUI(simState);
      hud.syncLensUI(lensController);
      resetWorldPhotons();
    }
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

  if (simState.isMoving && !lensController.isDragging && now - simState.lastMoveTime > 120) {
    simState.isMoving = false;
    pacer.resetAutoSpp(false, simState.cleanMotionMode);
    setTraceScale(1.0);
  }

  pacer.adjustAutoSpp(dt, simState.isMoving, simState.cleanMotionMode, targetFrameMs);

  const isDiffraction = sceneManager.activeSceneId === 1;
  const query = pacer.beginGpuQuery();

  pipeline.renderFrame({
    activeSceneId: sceneManager.activeSceneId,
    denoiseEnabled: simState.denoiseEnabled,
    sampleCount: simState.sampleCount,
    samplesPerFrame: pacer.samplesPerFrame,
    airPhotonFrameCount: simState.airPhotonFrameCount,
    worldPhotonFrameCount: simState.worldPhotonFrameCount
  });

  pacer.endGpuQuery(query, sceneManager.activeSceneId);

  simState.sampleCount += pacer.samplesPerFrame;
  if (isDiffraction) {
    simState.worldPhotonFrameCount += 1;
    simState.airPhotonFrameCount += 1;
  }

  hud.updateStats({
    sampleCount: simState.sampleCount,
    samplesPerFrame: pacer.samplesPerFrame,
    fps: Math.round(1000 / pacer.smoothedFrameMs),
    gpuMs: pacer.lastGpuMs,
    isDiffraction,
    worldPhotonFrameCount: simState.worldPhotonFrameCount,
    traceSize,
    renderScale,
    bufferLabel
  });
}

requestAnimationFrame(animate);