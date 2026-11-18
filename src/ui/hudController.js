import { MAX_FPS_SLIDER } from '../core/framePacer.js';
import { LENS_CATALOG } from '../scenes/lensInteraction.js';

const C_NM_THZ = 299792.458;

function normalizeDeg(deg) {
  return ((((deg + 180) % 360) + 360) % 360) - 180;
}

function formatFreqText(laserMode, customLaserLambda) {
  if (laserMode === 0) return '564 THz · 532 nm';
  if (laserMode === 1) return '461 THz · 650 nm';
  if (laserMode === 2) return '740 THz · 405 nm';
  if (laserMode === 3) return '416–789 THz · Branco';
  if (laserMode === 4) return 'Dual 650 + 405 nm';
  if (laserMode === 5) return 'Triplo 650·532·405';

  const nm = Math.round(customLaserLambda);
  const thz = Math.round(C_NM_THZ / customLaserLambda);
  if (nm < 380) return `${thz} THz · ${nm} nm (UV)`;
  if (nm > 720) return `${thz} THz · ${nm} nm (IR)`;
  return `${thz} THz · ${nm} nm`;
}

export function createHudController({
  isCoarsePointer,
  initialFpsLimit,
  initialCleanMotion,
  onSelectScene,
  onSelectLaserMode,
  onChangeLaserFrequency,
  onChangeLaserBeamRadius,
  onChangeLaserYaw,
  onChangeLaserPitch,
  onResetLaser,
  onToggleSlitPlate,
  onToggleSlit,
  onSelectLens,
  onChangeLensHeight,
  onChangeLensYaw,
  onPlaceLensInFront,
  onResetLens,
  onToggleDenoise,
  onToggleCleanMotion,
  onChangeFpsLimit,
  onResetCamera,
  onResetScene
}) {
  const statsEl = document.getElementById('stats');
  const menuOpenBtn = document.getElementById('menu-open-btn');
  const menuCloseBtn = document.getElementById('menu-close-btn');
  const sceneButtons = Array.from(document.querySelectorAll('[data-scene]'));
  const laserSection = document.getElementById('laser-section');
  const laserButtons = Array.from(document.querySelectorAll('[data-laser]'));
  const laserFreqSlider = document.getElementById('laser-freq-slider');
  const laserFreqValue = document.getElementById('laser-freq-value');

  const laserDiameterSlider = document.getElementById('laser-diameter-slider');
  const laserDiameterValue = document.getElementById('laser-diameter-value');
  const laserYawSlider = document.getElementById('laser-yaw-slider');
  const laserYawValue = document.getElementById('laser-yaw-value');
  const laserPitchSlider = document.getElementById('laser-pitch-slider');
  const laserPitchValue = document.getElementById('laser-pitch-value');
  const resetLaserBtn = document.getElementById('reset-laser-btn');

  const togglePlateBtn = document.getElementById('toggle-plate');
  const slitShutterBlock = document.getElementById('slit-shutter-block');
  const toggleSlitBtn = document.getElementById('toggle-slit');

  const lensButtons = Array.from(document.querySelectorAll('[data-lens]'));
  const lensControlsBlock = document.getElementById('lens-controls-block');
  const lensSelectedLabel = document.getElementById('lens-selected-label');
  const lensHeightSlider = document.getElementById('lens-height-slider');
  const lensHeightValue = document.getElementById('lens-height-value');
  const lensYawSlider = document.getElementById('lens-yaw-slider');
  const lensYawValue = document.getElementById('lens-yaw-value');
  const lensToLaserBtn = document.getElementById('lens-to-laser-btn');
  const lensResetBtn = document.getElementById('lens-reset-btn');
  const lensDeselectBtn = document.getElementById('lens-deselect-btn');

  const toggleDenoiseBtn = document.getElementById('toggle-denoise');
  const toggleCleanMoveBtn = document.getElementById('toggle-clean-move');
  const fpsLimitSlider = document.getElementById('fps-limit-slider');
  const fpsLimitValue = document.getElementById('fps-limit-value');
  const resetCameraBtn = document.getElementById('reset-camera-btn');
  const resetSceneBtn = document.getElementById('reset-scene-btn');
  const fullscreenBtn = document.getElementById('fullscreen-btn');

  let menuOpen = !isCoarsePointer && window.innerWidth >= 1024;

  function setMenuOpen(open) {
    menuOpen = open;
    document.body.classList.toggle('menu-open', open);
    menuOpenBtn.setAttribute('aria-expanded', String(open));
  }

  setMenuOpen(menuOpen);
  menuOpenBtn.addEventListener('click', () => setMenuOpen(true));
  menuCloseBtn.addEventListener('click', () => setMenuOpen(false));

  const canFullscreen = Boolean(document.fullscreenEnabled || document.webkitFullscreenEnabled);
  if (!canFullscreen) fullscreenBtn.hidden = true;

  function updateFullscreenBtn() {
    const isFs = Boolean(document.fullscreenElement || document.webkitFullscreenElement);
    fullscreenBtn.textContent = isFs ? 'Sair Tela Cheia' : 'Tela Cheia';
    fullscreenBtn.classList.toggle('active', isFs);
  }

  fullscreenBtn.addEventListener('click', async () => {
    try {
      if (!document.fullscreenElement && !document.webkitFullscreenElement) {
        const el = document.documentElement;
        if (el.requestFullscreen) await el.requestFullscreen();
        else if (el.webkitRequestFullscreen) await el.webkitRequestFullscreen();
        if (screen.orientation?.lock) screen.orientation.lock('landscape').catch(() => {});
      } else {
        if (document.exitFullscreen) await document.exitFullscreen();
        else if (document.webkitExitFullscreen) await document.webkitExitFullscreen();
      }
    } catch (err) {
      console.warn('Tela cheia indisponível:', err);
    }
  });

  document.addEventListener('fullscreenchange', updateFullscreenBtn);
  document.addEventListener('webkitfullscreenchange', updateFullscreenBtn);

  function syncFpsUI(fps) {
    fpsLimitSlider.value = String(fps);
    fpsLimitValue.textContent = fps >= MAX_FPS_SLIDER ? 'VSync (Máx)' : `${fps} FPS`;
  }

  function syncSceneUI(activeSceneId) {
    sceneButtons.forEach((btn) => btn.classList.toggle('active', Number(btn.dataset.scene) === activeSceneId));
    laserSection.hidden = activeSceneId !== 1;
  }

  function syncLaserUI({
    laserMode,
    customLaserLambda,
    slit1Blocked,
    slitPlateEnabled,
    laserBeamRadius,
    laserYawDeg,
    laserPitchDeg
  }) {
    laserButtons.forEach((btn) => btn.classList.toggle('active', Number(btn.dataset.laser) === laserMode));

    if (laserMode === 0) laserFreqSlider.value = '564';
    else if (laserMode === 1) laserFreqSlider.value = '461';
    else if (laserMode === 2) laserFreqSlider.value = '740';
    else if (laserMode === 6) laserFreqSlider.value = String(Math.round(C_NM_THZ / customLaserLambda));
    laserFreqValue.textContent = formatFreqText(laserMode, customLaserLambda);

    laserDiameterSlider.value = String(laserBeamRadius);
    laserDiameterValue.textContent = `${(laserBeamRadius * 200).toFixed(1)} cm`;

    laserYawSlider.value = String(laserYawDeg);
    laserYawValue.textContent = `${laserYawDeg}°`;

    laserPitchSlider.value = String(laserPitchDeg);
    laserPitchValue.textContent = `${laserPitchDeg}°`;

    const plateOn = slitPlateEnabled === 1;
    togglePlateBtn.textContent = `Plaquinha: ${plateOn ? 'Na Mesa' : 'Removida'} (P)`;
    togglePlateBtn.classList.toggle('active', plateOn);
    togglePlateBtn.classList.toggle('off', !plateOn);
    slitShutterBlock.hidden = !plateOn;

    toggleSlitBtn.textContent = `Fenda 1: ${slit1Blocked ? 'Tampada' : 'Aberta'} (B)`;
    toggleSlitBtn.classList.toggle('blocked', slit1Blocked === 1);
  }

  function syncLensUI({ selectedLens, positions, yaws }) {
    lensButtons.forEach((btn) => btn.classList.toggle('active', Number(btn.dataset.lens) === selectedLens));
    lensControlsBlock.hidden = selectedLens < 0;
    if (selectedLens < 0) return;

    const info = LENS_CATALOG[selectedLens];
    const pos = positions[selectedLens];
    const yawDeg = normalizeDeg(Math.round((yaws[selectedLens] * 180) / Math.PI));

    lensSelectedLabel.textContent = `Selecionada: ${info.name}`;
    lensHeightSlider.value = String(pos.y);
    lensHeightValue.textContent = Math.abs(pos.y + 0.36) < 0.015 ? 'Alinhada (Laser)' : `${pos.y.toFixed(2)} m`;
    lensYawSlider.value = String(yawDeg);
    lensYawValue.textContent = `${yawDeg}°`;
  }

  function syncDenoiseUI(enabled) {
    toggleDenoiseBtn.textContent = `Denoise À-Trous: ${enabled ? 'ON' : 'OFF'} (D)`;
    toggleDenoiseBtn.classList.toggle('active', enabled);
    toggleDenoiseBtn.classList.toggle('off', !enabled);
  }

  function syncCleanMotionUI(enabled) {
    toggleCleanMoveBtn.textContent = `Movimento Limpo: ${enabled ? 'ON' : 'OFF'} (Q)`;
    toggleCleanMoveBtn.classList.toggle('active', enabled);
    toggleCleanMoveBtn.classList.toggle('off', !enabled);
  }

  laserFreqSlider.addEventListener('input', () => {
    const thz = Number(laserFreqSlider.value);
    const nm = C_NM_THZ / thz;
    laserFreqValue.textContent = formatFreqText(6, nm);
    onChangeLaserFrequency(nm);
  });

  laserDiameterSlider.addEventListener('input', () => {
    const r = Number(laserDiameterSlider.value);
    laserDiameterValue.textContent = `${(r * 200).toFixed(1)} cm`;
    onChangeLaserBeamRadius(r);
  });

  laserYawSlider.addEventListener('input', () => {
    const deg = Number(laserYawSlider.value);
    laserYawValue.textContent = `${deg}°`;
    onChangeLaserYaw(deg);
  });

  laserPitchSlider.addEventListener('input', () => {
    const deg = Number(laserPitchSlider.value);
    laserPitchValue.textContent = `${deg}°`;
    onChangeLaserPitch(deg);
  });

  resetLaserBtn.addEventListener('click', onResetLaser);
  togglePlateBtn.addEventListener('click', onToggleSlitPlate);
  toggleSlitBtn.addEventListener('click', onToggleSlit);

  lensButtons.forEach((btn) => btn.addEventListener('click', () => onSelectLens(Number(btn.dataset.lens))));
  lensHeightSlider.addEventListener('input', () => {
    const y = Number(lensHeightSlider.value);
    lensHeightValue.textContent = Math.abs(y + 0.36) < 0.015 ? 'Alinhada (Laser)' : `${y.toFixed(2)} m`;
    onChangeLensHeight(y);
  });
  lensYawSlider.addEventListener('input', () => {
    const deg = Number(lensYawSlider.value);
    lensYawValue.textContent = `${deg}°`;
    onChangeLensYaw(deg);
  });
  lensToLaserBtn.addEventListener('click', onPlaceLensInFront);
  lensResetBtn.addEventListener('click', onResetLens);
  lensDeselectBtn.addEventListener('click', () => onSelectLens(-1));

  fpsLimitSlider.addEventListener('input', () => {
    const fps = Number(fpsLimitSlider.value);
    syncFpsUI(fps);
    onChangeFpsLimit(fps);
  });

  sceneButtons.forEach((btn) => btn.addEventListener('click', () => onSelectScene(Number(btn.dataset.scene))));
  laserButtons.forEach((btn) => btn.addEventListener('click', () => onSelectLaserMode(Number(btn.dataset.laser))));
  toggleDenoiseBtn.addEventListener('click', onToggleDenoise);
  toggleCleanMoveBtn.addEventListener('click', onToggleCleanMotion);
  resetCameraBtn.addEventListener('click', onResetCamera);
  resetSceneBtn.addEventListener('click', onResetScene);

  window.addEventListener('keydown', (e) => {
    const k = e.key.toLowerCase();
    if (k === 'd') onToggleDenoise();
    else if (k === 'q') onToggleCleanMotion();
    else if (k === 's') onSelectScene(null);
    else if (k === 'l') onSelectLaserMode(null);
    else if (k === 'b') onToggleSlit();
    else if (k === 'p') onToggleSlitPlate();
    else if (k === 'm') setMenuOpen(!menuOpen);
  });

  syncFpsUI(initialFpsLimit);
  syncCleanMotionUI(initialCleanMotion);

  function updateStats({
    sampleCount,
    samplesPerFrame,
    fps,
    gpuMs,
    isDiffraction,
    worldPhotonFrameCount,
    traceSize,
    renderScale,
    bufferLabel
  }) {
    const gpuInfo = gpuMs !== null ? ` · ${gpuMs.toFixed(1)}ms` : '';
    const photonInfo = isDiffraction ? ` · Atlas ${worldPhotonFrameCount}f` : '';
    statsEl.textContent =
      `${sampleCount} spp (+${samplesPerFrame}) · ${fps} FPS${gpuInfo}${photonInfo} · ` +
      `${traceSize.x}x${traceSize.y} (${renderScale}x) · ${bufferLabel}`;
  }

  return {
    statsEl,
    syncSceneUI,
    syncLaserUI,
    syncLensUI,
    syncDenoiseUI,
    syncCleanMotionUI,
    updateStats
  };
}