import { MAX_FPS_SLIDER } from '../core/framePacer.js';

export function createHudController({
  isCoarsePointer,
  hasFloatBlend,
  initialFpsLimit,
  initialCleanMotion,
  onSelectScene,
  onSelectSimMode,
  onSelectLaserMode,
  onToggleSlit,
  onToggleDenoise,
  onToggleCleanMotion,
  onChangeFpsLimit,
  onResetCamera
}) {
  const statsEl = document.getElementById('stats');
  const menuOpenBtn = document.getElementById('menu-open-btn');
  const menuCloseBtn = document.getElementById('menu-close-btn');
  const sceneButtons = Array.from(document.querySelectorAll('[data-scene]'));
  const laserSection = document.getElementById('laser-section');
  const simRow = document.getElementById('sim-row');
  const simButtons = Array.from(document.querySelectorAll('[data-sim]'));
  const laserButtons = Array.from(document.querySelectorAll('[data-laser]'));
  const toggleSlitBtn = document.getElementById('toggle-slit');
  const toggleDenoiseBtn = document.getElementById('toggle-denoise');
  const toggleCleanMoveBtn = document.getElementById('toggle-clean-move');
  const fpsLimitSlider = document.getElementById('fps-limit-slider');
  const fpsLimitValue = document.getElementById('fps-limit-value');
  const resetCameraBtn = document.getElementById('reset-camera-btn');
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
    simRow.hidden = !hasFloatBlend;
  }

  function syncLaserUI({ laserSimMode, laserMode, slit1Blocked }) {
    simButtons.forEach((btn) => btn.classList.toggle('active', Number(btn.dataset.sim) === laserSimMode));
    laserButtons.forEach((btn) => btn.classList.toggle('active', Number(btn.dataset.laser) === laserMode));
    toggleSlitBtn.textContent = `Fenda 1: ${slit1Blocked ? 'Tampada' : 'Aberta'}`;
    toggleSlitBtn.classList.toggle('blocked', slit1Blocked === 1);
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

  fpsLimitSlider.addEventListener('input', () => {
    const fps = Number(fpsLimitSlider.value);
    syncFpsUI(fps);
    onChangeFpsLimit(fps);
  });

  sceneButtons.forEach((btn) => btn.addEventListener('click', () => onSelectScene(Number(btn.dataset.scene))));
  simButtons.forEach((btn) => btn.addEventListener('click', () => onSelectSimMode(Number(btn.dataset.sim))));
  laserButtons.forEach((btn) => btn.addEventListener('click', () => onSelectLaserMode(Number(btn.dataset.laser))));
  toggleSlitBtn.addEventListener('click', onToggleSlit);
  toggleDenoiseBtn.addEventListener('click', onToggleDenoise);
  toggleCleanMoveBtn.addEventListener('click', onToggleCleanMotion);
  resetCameraBtn.addEventListener('click', onResetCamera);

  window.addEventListener('keydown', (e) => {
    const k = e.key.toLowerCase();
    if (k === 'd') onToggleDenoise();
    else if (k === 'q') onToggleCleanMotion();
    else if (k === 's') onSelectScene(null);
    else if (k === 'f') onSelectSimMode(null);
    else if (k === 'l') onSelectLaserMode(null);
    else if (k === 'b') onToggleSlit();
    else if (k === 'm') setMenuOpen(!menuOpen);
  });

  syncFpsUI(initialFpsLimit);
  syncCleanMotionUI(initialCleanMotion);

  function updateStats({
    sampleCount,
    samplesPerFrame,
    fps,
    gpuMs,
    useForwardPhotons,
    worldPhotonFrameCount,
    traceSize,
    renderScale,
    bufferLabel
  }) {
    const gpuInfo = gpuMs !== null ? ` · ${gpuMs.toFixed(1)}ms` : '';
    const photonInfo = useForwardPhotons ? ` · Atlas ${worldPhotonFrameCount}f` : '';
    statsEl.textContent =
      `${sampleCount} spp (+${samplesPerFrame}) · ${fps} FPS${gpuInfo}${photonInfo} · ` +
      `${traceSize.x}x${traceSize.y} (${renderScale}x) · ${bufferLabel}`;
  }

  return {
    statsEl,
    syncSceneUI,
    syncLaserUI,
    syncDenoiseUI,
    syncCleanMotionUI,
    updateStats
  };
}