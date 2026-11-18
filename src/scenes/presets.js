import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { assembleShader } from '../shaders/assembleShader.js';
import quadVert from '../shaders/quad.vert.glsl?raw';
import cornellFrag from '../shaders/pathTracer.frag.glsl?raw';
import diffractionFrag from '../shaders/diffraction.frag.glsl?raw';

export const LASER_PIVOT = new THREE.Vector3(-1.37515, -0.36, 0.80119);
const BASE_LASER_YAW = Math.atan2(0.34394, -0.93899);

export function computeLaserBasis(yawDeg, pitchDeg) {
  const yaw = BASE_LASER_YAW + THREE.MathUtils.degToRad(yawDeg);
  const pitch = THREE.MathUtils.degToRad(pitchDeg);
  const cosP = Math.cos(pitch);
  const sinP = Math.sin(pitch);

  const dir = new THREE.Vector3(Math.sin(yaw) * cosP, sinP, Math.cos(yaw) * cosP).normalize();
  const right = new THREE.Vector3(-Math.cos(yaw), 0, Math.sin(yaw)).normalize();
  const up = new THREE.Vector3().crossVectors(right, dir).normalize();
  return { dir, right, up };
}

export const SCENE_PRESETS = [
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
    noiseScale: 1.05,
    exposure: 1.15
  }
];

export function createSceneManager({ domElement, traceSize, blackTex, onCameraChange }) {
  const camera = new THREE.PerspectiveCamera(42, window.innerWidth / window.innerHeight, 0.1, 100);
  const controls = new OrbitControls(camera, domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.minDistance = 0.8;
  controls.maxDistance = 8.5;

  const viewProjMatrix = new THREE.Matrix4();
  let suppressMove = false;
  let activeSceneId = 0;

  function buildMaterial(fragmentSource, extraUniforms = {}) {
    return new THREE.RawShaderMaterial({
      glslVersion: THREE.GLSL3,
      vertexShader: quadVert,
      fragmentShader: assembleShader(fragmentSource),
      depthTest: false,
      depthWrite: false,
      uniforms: {
        uAccumTexture: { value: null },
        uResolution: { value: traceSize.clone() },
        uSampleCount: { value: 0 },
        uSamplesPerFrame: { value: 1 },
        uCamPos: { value: new THREE.Vector3() },
        uCamMatrix: { value: new THREE.Matrix4() },
        uTanHalfFov: { value: Math.tan(THREE.MathUtils.degToRad(camera.fov * 0.5)) },
        uAspect: { value: camera.aspect },
        ...extraUniforms
      }
    });
  }

  const materials = [buildMaterial(SCENE_PRESETS[0].frag), null];

  controls.addEventListener('change', () => {
    if (!suppressMove) onCameraChange();
  });

  function getOrCreateMaterial(sceneId, laserState, lensState) {
    if (!materials[sceneId]) {
      const basis = computeLaserBasis(laserState.laserYawDeg ?? 0, laserState.laserPitchDeg ?? 0);
      const extra = sceneId === 1
        ? {
            uWorldPhotonTex: { value: blackTex },
            uLaserMode: { value: laserState.laserMode },
            uCustomLaserLambda: { value: laserState.customLaserLambda ?? 532.0 },
            uSlit1Blocked: { value: laserState.slit1Blocked },
            uSlitPlateEnabled: { value: laserState.slitPlateEnabled ?? 1 },
            uLaserDir: { value: basis.dir.clone() },
            uLaserBeamRadius: { value: laserState.laserBeamRadius ?? 0.056 },
            uLensPos: { value: lensState ? lensState.positions : [new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3()] },
            uLensYaw: { value: lensState ? lensState.yaws : [0, 0, 0, 0] },
            uSelectedLens: { value: lensState ? lensState.selectedLens : -1 }
          }
        : {};
      materials[sceneId] = buildMaterial(SCENE_PRESETS[sceneId].frag, extra);
    }
    return materials[sceneId];
  }

  function resetCameraView() {
    const preset = SCENE_PRESETS[activeSceneId];
    suppressMove = true;
    camera.position.copy(preset.camPos);
    controls.target.copy(preset.target);
    controls.update();
    suppressMove = false;
  }

  function switchScene(nextId, laserState, currentTraceSize, lensState = null) {
    activeSceneId = nextId;
    const preset = SCENE_PRESETS[activeSceneId];
    const mat = getOrCreateMaterial(activeSceneId, laserState, lensState);

    mat.uniforms.uResolution.value.copy(currentTraceSize);
    mat.uniforms.uAspect.value = camera.aspect;
    mat.uniforms.uTanHalfFov.value = Math.tan(THREE.MathUtils.degToRad(camera.fov * 0.5));

    resetCameraView();
    return { preset, material: mat };
  }

  function updateProjection(width, height, currentTraceSize) {
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    const tanHalfFov = Math.tan(THREE.MathUtils.degToRad(camera.fov * 0.5));

    for (const mat of materials) {
      if (mat) {
        mat.uniforms.uResolution.value.copy(currentTraceSize);
        mat.uniforms.uAspect.value = camera.aspect;
        mat.uniforms.uTanHalfFov.value = tanHalfFov;
      }
    }
    return tanHalfFov;
  }

  function updateTraceResolution(currentTraceSize) {
    for (const mat of materials) {
      if (mat) mat.uniforms.uResolution.value.copy(currentTraceSize);
    }
  }

  function updateCameraMatrices() {
    controls.update();
    camera.updateMatrixWorld();
    camera.matrixWorldInverse.copy(camera.matrixWorld).invert();
    viewProjMatrix.multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
  }

  return {
    camera,
    controls,
    viewProjMatrix,
    materials,
    get activeSceneId() { return activeSceneId; },
    switchScene,
    resetCameraView,
    updateProjection,
    updateTraceResolution,
    updateCameraMatrices
  };
}