import * as THREE from 'three';

export const LENS_CATALOG = [
  { id: 0, name: 'Biconvexa',     short: 'L1 Biconvexa',  defaultPos: [1.42, -0.36, -0.90], defaultYaw: -0.35 },
  { id: 1, name: 'Bicôncava',     short: 'L2 Bicôncava',  defaultPos: [1.42, -0.36, -0.30], defaultYaw: -0.35 },
  { id: 2, name: 'Plano-Convexa', short: 'L3 Plano-Conv.', defaultPos: [1.42, -0.36,  0.30], defaultYaw: -0.35 },
  { id: 3, name: 'Cilíndrica',    short: 'L4 Cilíndrica', defaultPos: [1.42, -0.36,  0.90], defaultYaw: -0.35 }
];

const LENS_PICK_RADIUS = 0.24;

function clampLensPos(pos) {
  pos.x = THREE.MathUtils.clamp(pos.x, -1.55, 1.55);
  pos.y = THREE.MathUtils.clamp(pos.y, -0.58, 0.95);
  pos.z = THREE.MathUtils.clamp(pos.z, -1.18, 1.55);
}

export function createLensController({
  domElement,
  camera,
  controls,
  getActiveSceneId,
  onSelectLens,
  onLensChanged,
  onDragEnd
}) {
  const positions = LENS_CATALOG.map((item) => new THREE.Vector3(...item.defaultPos));
  const yaws = LENS_CATALOG.map((item) => item.defaultYaw);

  let selectedLens = -1;
  let isDragging = false;
  let activePointerId = null;

  const raycaster = new THREE.Raycaster();
  const dragPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const dragHit = new THREE.Vector3();
  const dragOffset = new THREE.Vector3();
  const tmpNdc = new THREE.Vector2();
  const tmpClosest = new THREE.Vector3();

  function getPointerNdc(e) {
    const rect = domElement.getBoundingClientRect();
    tmpNdc.set(
      ((e.clientX - rect.left) / rect.width) * 2 - 1,
      -((e.clientY - rect.top) / rect.height) * 2 + 1
    );
  }

  function pickLens(e) {
    getPointerNdc(e);
    raycaster.setFromCamera(tmpNdc, camera);
    const ray = raycaster.ray;

    let bestIdx = -1;
    let bestDist = Infinity;

    for (let i = 0; i < positions.length; i++) {
      const center = positions[i];
      const distSq = ray.distanceSqToPoint(center);
      if (distSq <= LENS_PICK_RADIUS * LENS_PICK_RADIUS) {
        const d = ray.origin.distanceTo(center);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
        continue;
      }

      const pedTop = center.y - 0.22;
      if (pedTop > -0.79) {
        const start = tmpClosest.set(center.x, -0.80, center.z);
        const end = new THREE.Vector3(center.x, pedTop, center.z);
        const segDistSq = ray.distanceSqToSegment(start, end);
        if (segDistSq <= 0.045 * 0.045) {
          const d = ray.origin.distanceTo(center);
          if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
          }
        }
      }
    }

    return bestIdx;
  }

  function handlePointerDown(e) {
    if (getActiveSceneId() !== 1) return;
    if (e.pointerType === 'mouse' && e.button !== 0) return;

    const hitIdx = pickLens(e);
    if (hitIdx < 0) return;

    selectedLens = hitIdx;
    isDragging = true;
    activePointerId = e.pointerId;
    controls.enabled = false;

    dragPlane.set(new THREE.Vector3(0, 1, 0), -positions[hitIdx].y);
    getPointerNdc(e);
    raycaster.setFromCamera(tmpNdc, camera);
    if (raycaster.ray.intersectPlane(dragPlane, dragHit)) {
      dragOffset.copy(positions[hitIdx]).sub(dragHit);
    } else {
      dragOffset.set(0, 0, 0);
    }

    if (domElement.setPointerCapture) {
      try { domElement.setPointerCapture(e.pointerId); } catch {}
    }

    onSelectLens(hitIdx);
    onLensChanged(true);
  }

  function handlePointerMove(e) {
    if (!isDragging || e.pointerId !== activePointerId || selectedLens < 0) return;

    getPointerNdc(e);
    raycaster.setFromCamera(tmpNdc, camera);
    if (raycaster.ray.intersectPlane(dragPlane, dragHit)) {
      const target = positions[selectedLens];
      target.x = dragHit.x + dragOffset.x;
      target.z = dragHit.z + dragOffset.z;
      clampLensPos(target);
      onLensChanged(true);
    }
  }

  function stopDragging(e) {
    if (!isDragging || (e && e.pointerId !== activePointerId)) return;
    isDragging = false;
    activePointerId = null;
    controls.enabled = true;
    onDragEnd();
  }

  domElement.addEventListener('pointerdown', handlePointerDown);
  window.addEventListener('pointermove', handlePointerMove);
  window.addEventListener('pointerup', stopDragging);
  window.addEventListener('pointercancel', stopDragging);

  function selectLens(idx) {
    selectedLens = idx;
    onSelectLens(idx);
    onLensChanged(false);
  }

  function setSelectedHeight(y) {
    if (selectedLens < 0) return;
    positions[selectedLens].y = y;
    clampLensPos(positions[selectedLens]);
    onLensChanged(false);
  }

  function setSelectedYawDeg(deg) {
    if (selectedLens < 0) return;
    yaws[selectedLens] = THREE.MathUtils.degToRad(deg);
    onLensChanged(false);
  }

  function placeSelectedInFrontOfLaser(laserPivot, laserDir, distance = 0.90) {
    if (selectedLens < 0) return;
    const p = positions[selectedLens];
    p.copy(laserPivot).addScaledVector(laserDir, distance);
    clampLensPos(p);
    yaws[selectedLens] = Math.atan2(laserDir.x, laserDir.z);
    onLensChanged(false);
  }

  function resetSelectedToCorner() {
    if (selectedLens < 0) return;
    const def = LENS_CATALOG[selectedLens];
    positions[selectedLens].set(...def.defaultPos);
    yaws[selectedLens] = def.defaultYaw;
    onLensChanged(false);
  }

  function resetAllLenses() {
    selectedLens = -1;
    isDragging = false;
    activePointerId = null;
    controls.enabled = true;
    for (let i = 0; i < LENS_CATALOG.length; i++) {
      const def = LENS_CATALOG[i];
      positions[i].set(...def.defaultPos);
      yaws[i] = def.defaultYaw;
    }
  }

  return {
    positions,
    yaws,
    get selectedLens() { return selectedLens; },
    get isDragging() { return isDragging; },
    selectLens,
    setSelectedHeight,
    setSelectedYawDeg,
    placeSelectedInFrontOfLaser,
    resetSelectedToCorner,
    resetAllLenses
  };
}