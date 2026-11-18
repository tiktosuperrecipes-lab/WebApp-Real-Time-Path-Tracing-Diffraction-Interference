export const MAX_SPP_PER_FRAME = 64;
export const MAX_MOTION_SPP = 32;
export const MAX_FPS_SLIDER = 245;

export function createFramePacer({ gl, timerExt, initialFps = 60 }) {
  let fpsLimit = initialFps;
  let samplesPerFrame = 1;
  let lastIdleSpp = 8;
  let motionSpp = 6;
  let prevRafTime = performance.now();
  let lastRenderTimestamp = performance.now();
  let nextFrameTargetTime = 0;
  let smoothedFrameMs = 1000 / 60;
  let baselineVsyncMs = 16.67;
  let vsyncSampleFrames = 0;
  let hitVsyncCeiling = false;
  let sppAdjustCooldown = 0;
  let lastGpuMs = null;

  const pendingQueries = [];

  function getTargetFrameMs() {
    return fpsLimit >= MAX_FPS_SLIDER ? 0 : 1000 / fpsLimit;
  }

  function setFpsLimit(nextFps) {
    fpsLimit = nextFps;
    nextFrameTargetTime = 0;
    hitVsyncCeiling = false;
    sppAdjustCooldown = 2;
  }

  function tickAndShouldRender(now) {
    const rafDt = now - prevRafTime;
    prevRafTime = now;
    if (vsyncSampleFrames < 20 && rafDt >= 3.5 && rafDt <= 35.0) {
      baselineVsyncMs = vsyncSampleFrames === 0 ? rafDt : Math.min(baselineVsyncMs, rafDt * 1.02);
      vsyncSampleFrames += 1;
    }

    const targetFrameMs = getTargetFrameMs();
    if (targetFrameMs > 0) {
      if (nextFrameTargetTime > 0 && now < nextFrameTargetTime - 1.5) {
        return { shouldRender: false, dt: 0, targetFrameMs };
      }
      if (nextFrameTargetTime === 0 || now - nextFrameTargetTime > targetFrameMs * 2.0) {
        nextFrameTargetTime = now + targetFrameMs;
      } else {
        nextFrameTargetTime += targetFrameMs;
      }
    }

    const dt = Math.min(Math.max(now - lastRenderTimestamp, 1), 250);
    lastRenderTimestamp = now;
    smoothedFrameMs = smoothedFrameMs * 0.85 + dt * 0.15;
    return { shouldRender: true, dt, targetFrameMs };
  }

  function pollGpuTimer(activeSceneId) {
    if (!timerExt || pendingQueries.length === 0) return;

    while (pendingQueries.length > 0) {
      const oldest = pendingQueries[0];
      if (!gl.getQueryParameter(oldest.query, gl.QUERY_RESULT_AVAILABLE)) break;

      const disjoint = gl.getParameter(timerExt.GPU_DISJOINT_EXT);
      if (!disjoint && oldest.sceneId === activeSceneId) {
        const ms = gl.getQueryParameter(oldest.query, gl.QUERY_RESULT) / 1e6;
        lastGpuMs = lastGpuMs === null ? ms : lastGpuMs * 0.6 + ms * 0.4;
      }
      gl.deleteQuery(oldest.query);
      pendingQueries.shift();
    }
  }

  function adjustAutoSpp(dt, isMoving, cleanMotionMode, targetFrameMs) {
    const maxCap = isMoving ? MAX_MOTION_SPP : MAX_SPP_PER_FRAME;
    if (!isMoving || cleanMotionMode) {
      if (sppAdjustCooldown > 0) {
        sppAdjustCooldown -= 1;
      } else {
        const effectivePeriodMs =
          targetFrameMs > 0 && targetFrameMs >= baselineVsyncMs * 1.5
            ? targetFrameMs
            : baselineVsyncMs;
        const budgetMs = Math.max(4.5, effectivePeriodMs * 0.78);

        if (lastGpuMs !== null) {
          if (lastGpuMs < budgetMs * 0.85 && samplesPerFrame < maxCap) {
            const step = Math.max(1, Math.floor(samplesPerFrame * 0.25));
            samplesPerFrame = Math.min(maxCap, samplesPerFrame + step);
            sppAdjustCooldown = 3;
          } else if (lastGpuMs > budgetMs * 1.08 && samplesPerFrame > 1) {
            samplesPerFrame = Math.max(1, Math.floor(samplesPerFrame * 0.82));
            sppAdjustCooldown = 3;
          }
        } else {
          const ceilingRef = targetFrameMs > 0 ? Math.max(baselineVsyncMs, targetFrameMs) : baselineVsyncMs;
          if (dt > ceilingRef * 1.22 && samplesPerFrame > 1) {
            samplesPerFrame = Math.max(1, Math.floor(samplesPerFrame * 0.80));
            hitVsyncCeiling = true;
            sppAdjustCooldown = 10;
          } else if (!hitVsyncCeiling && dt <= ceilingRef * 1.15 && samplesPerFrame < maxCap) {
            const step = Math.max(1, Math.floor(samplesPerFrame * 0.25));
            samplesPerFrame = Math.min(maxCap, samplesPerFrame + step);
            sppAdjustCooldown = 4;
          }
        }
      }
    }

    if (isMoving && cleanMotionMode) motionSpp = samplesPerFrame;
    else if (!isMoving) lastIdleSpp = samplesPerFrame;
  }

  function resetAutoSpp(isMoving, cleanMotionMode) {
    samplesPerFrame = isMoving && cleanMotionMode ? motionSpp : 1;
    sppAdjustCooldown = 3;
    hitVsyncCeiling = false;
    lastGpuMs = null;
  }

  function prepareMotionSpp(cleanMotionMode) {
    motionSpp = Math.min(MAX_MOTION_SPP, Math.max(4, Math.floor(lastIdleSpp * 0.85)));
    samplesPerFrame = cleanMotionMode ? motionSpp : 1;
  }

  function setSamplesPerFrame(n) {
    samplesPerFrame = n;
  }

  function beginGpuQuery() {
    if (!timerExt || pendingQueries.length >= 4) return null;
    const q = gl.createQuery();
    gl.beginQuery(timerExt.TIME_ELAPSED_EXT, q);
    return q;
  }

  function endGpuQuery(query, activeSceneId) {
    if (!query) return;
    gl.endQuery(timerExt.TIME_ELAPSED_EXT);
    pendingQueries.push({ query, sceneId: activeSceneId });
  }

  return {
    get fpsLimit() { return fpsLimit; },
    get samplesPerFrame() { return samplesPerFrame; },
    get motionSpp() { return motionSpp; },
    get smoothedFrameMs() { return smoothedFrameMs; },
    get lastGpuMs() { return lastGpuMs; },
    setFpsLimit,
    setSamplesPerFrame,
    tickAndShouldRender,
    pollGpuTimer,
    adjustAutoSpp,
    resetAutoSpp,
    prepareMotionSpp,
    beginGpuQuery,
    endGpuQuery
  };
}