import * as THREE from 'three';
import { assembleShader } from '../shaders/assembleShader.js';
import { computeLaserBasis } from '../scenes/presets.js';
import quadVert from '../shaders/quad.vert.glsl?raw';
import photonVert from '../shaders/photon.vert.glsl?raw';
import photonFrag from '../shaders/photon.frag.glsl?raw';
import photonAccumFrag from '../shaders/photonAccum.frag.glsl?raw';
import denoiseFrag from '../shaders/denoise.frag.glsl?raw';
import displayFrag from '../shaders/display.frag.glsl?raw';

const ATROUS_STEPS = [0, 1, 2, 4];
const PHOTON_COUNT = 131072;

export function createRenderPipeline({ renderer, targets, sceneManager, traceSize }) {
  const quadCamera = new THREE.Camera();
  const quadGeometry = new THREE.PlaneGeometry(2, 2);

  const photonIndices = new Float32Array(PHOTON_COUNT);
  for (let i = 0; i < PHOTON_COUNT; i++) photonIndices[i] = i;

  const photonGeometry = new THREE.BufferGeometry();
  photonGeometry.setAttribute('aIndex', new THREE.BufferAttribute(photonIndices, 1));
  photonGeometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(PHOTON_COUNT * 3), 3));
  photonGeometry.boundingSphere = new THREE.Sphere(new THREE.Vector3(), 100);

  const initialBasis = computeLaserBasis(0, 0);

  const photonMaterial = new THREE.RawShaderMaterial({
    glslVersion: THREE.GLSL3,
    vertexShader: assembleShader(photonVert),
    fragmentShader: photonFrag,
    depthTest: false,
    depthWrite: false,
    transparent: true,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uViewProj: { value: new THREE.Matrix4() },
      uCamPos: { value: new THREE.Vector3() },
      uResolution: { value: traceSize.clone() },
      uTanHalfFov: { value: Math.tan(THREE.MathUtils.degToRad(sceneManager.camera.fov * 0.5)) },
      uFrameSeed: { value: 1 },
      uLaserMode: { value: 0 },
      uCustomLaserLambda: { value: 532.0 },
      uSlit1Blocked: { value: 0 },
      uSlitPlateEnabled: { value: 1 },
      uPhotonCount: { value: PHOTON_COUNT },
      uPassType: { value: 0 },
      uGBufferTex: { value: targets.blackTex },
      uLaserDir: { value: initialBasis.dir.clone() },
      uLaserRight: { value: initialBasis.right.clone() },
      uLaserUp: { value: initialBasis.up.clone() },
      uLaserBeamRadius: { value: 0.056 },
      uLensPos: { value: [new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3()] },
      uLensYaw: { value: [0, 0, 0, 0] },
      uSelectedLens: { value: -1 }
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
      uGBufferTex: { value: null },
      uAlbedoTex: { value: null },
      uCamMatrix: { value: new THREE.Matrix4() },
      uTanHalfFov: { value: Math.tan(THREE.MathUtils.degToRad(sceneManager.camera.fov * 0.5)) },
      uAspect: { value: sceneManager.camera.aspect },
      uTexSize: { value: new THREE.Vector2(traceSize.x, traceSize.y) },
      uPassIndex: { value: 0 },
      uStepSize: { value: 1 },
      uSampleCount: { value: 1 },
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
      uExtraTex: { value: targets.blackTex },
      uHasExtraTex: { value: 0 },
      uExposure: { value: 1.0 }
    }
  });

  const ptMesh = new THREE.Mesh(quadGeometry, sceneManager.materials[0]);
  const ptScene = new THREE.Scene();
  ptScene.add(ptMesh);

  const denoiseScene = new THREE.Scene();
  denoiseScene.add(new THREE.Mesh(quadGeometry, denoiseMaterial));

  const displayScene = new THREE.Scene();
  displayScene.add(new THREE.Mesh(quadGeometry, displayMaterial));

  let frameSeed = 1;

  function setActiveScene(material, preset) {
    ptMesh.material = material;
    denoiseMaterial.uniforms.uNoiseScale.value = preset.noiseScale;
    displayMaterial.uniforms.uExposure.value = preset.exposure;
  }

  function syncLaserUniforms({
    laserMode,
    customLaserLambda = 532.0,
    slit1Blocked,
    slitPlateEnabled = 1,
    laserBeamRadius = 0.056,
    laserYawDeg = 0,
    laserPitchDeg = 0
  }) {
    const basis = computeLaserBasis(laserYawDeg, laserPitchDeg);
    const diffMat = sceneManager.materials[1];
    if (diffMat) {
      diffMat.uniforms.uLaserMode.value = laserMode;
      diffMat.uniforms.uCustomLaserLambda.value = customLaserLambda;
      diffMat.uniforms.uSlit1Blocked.value = slit1Blocked;
      diffMat.uniforms.uSlitPlateEnabled.value = slitPlateEnabled;
      diffMat.uniforms.uLaserBeamRadius.value = laserBeamRadius;
      diffMat.uniforms.uLaserDir.value.copy(basis.dir);
    }
    photonMaterial.uniforms.uLaserMode.value = laserMode;
    photonMaterial.uniforms.uCustomLaserLambda.value = customLaserLambda;
    photonMaterial.uniforms.uSlit1Blocked.value = slit1Blocked;
    photonMaterial.uniforms.uSlitPlateEnabled.value = slitPlateEnabled;
    photonMaterial.uniforms.uLaserBeamRadius.value = laserBeamRadius;
    photonMaterial.uniforms.uLaserDir.value.copy(basis.dir);
    photonMaterial.uniforms.uLaserRight.value.copy(basis.right);
    photonMaterial.uniforms.uLaserUp.value.copy(basis.up);
  }

  function syncLensUniforms({ positions, yaws, selectedLens }) {
    const diffMat = sceneManager.materials[1];
    if (diffMat) {
      diffMat.uniforms.uLensPos.value = positions;
      diffMat.uniforms.uLensYaw.value = yaws;
      diffMat.uniforms.uSelectedLens.value = selectedLens;
    }
    photonMaterial.uniforms.uLensPos.value = positions;
    photonMaterial.uniforms.uLensYaw.value = yaws;
    photonMaterial.uniforms.uSelectedLens.value = selectedLens;
  }

  function updateResolution(newTraceSize, tanHalfFov) {
    photonMaterial.uniforms.uResolution.value.copy(newTraceSize);
    if (tanHalfFov !== undefined) photonMaterial.uniforms.uTanHalfFov.value = tanHalfFov;
    denoiseMaterial.uniforms.uTexSize.value.set(newTraceSize.x, newTraceSize.y);
  }

  function renderFrame({
    activeSceneId,
    denoiseEnabled,
    sampleCount,
    samplesPerFrame,
    airPhotonFrameCount,
    worldPhotonFrameCount
  }) {
    frameSeed = (frameSeed + 1) | 0;
    const isDiffraction = activeSceneId === 1;

    if (isDiffraction) {
      photonMaterial.uniforms.uPassType.value = 0;
      photonMaterial.uniforms.uFrameSeed.value = frameSeed;
      photonMaterial.uniforms.uGBufferTex.value = targets.blackTex;

      renderer.setRenderTarget(targets.worldPhotonFrameTarget);
      renderer.setClearColor(0x000000, 0);
      renderer.clearColor();
      renderer.render(photonScene, quadCamera);

      photonAccumMaterial.uniforms.uPrevPhotonTex.value = targets.readWorldPhoton.texture;
      photonAccumMaterial.uniforms.uCurrPhotonTex.value = targets.worldPhotonFrameTarget.texture;
      photonAccumMaterial.uniforms.uPhotonFrame.value = worldPhotonFrameCount;

      renderer.setRenderTarget(targets.writeWorldPhoton);
      renderer.render(photonAccumScene, quadCamera);
      targets.swapWorldPhoton();
    }

    const activeMat = ptMesh.material;
    activeMat.uniforms.uAccumTexture.value = targets.readAccum.textures[0];
    activeMat.uniforms.uSampleCount.value = sampleCount;
    activeMat.uniforms.uSamplesPerFrame.value = samplesPerFrame;
    activeMat.uniforms.uCamPos.value.copy(sceneManager.camera.position);
    activeMat.uniforms.uCamMatrix.value.copy(sceneManager.camera.matrixWorld);
    if (isDiffraction) {
      activeMat.uniforms.uWorldPhotonTex.value = targets.readWorldPhoton.texture;
    }

    renderer.setRenderTarget(targets.writeAccum);
    renderer.render(ptScene, quadCamera);

    if (isDiffraction) {
      photonMaterial.uniforms.uPassType.value = 1;
      photonMaterial.uniforms.uViewProj.value.copy(sceneManager.viewProjMatrix);
      photonMaterial.uniforms.uCamPos.value.copy(sceneManager.camera.position);
      photonMaterial.uniforms.uFrameSeed.value = frameSeed;
      photonMaterial.uniforms.uGBufferTex.value = targets.writeAccum.textures[1];

      renderer.setRenderTarget(targets.airFrameTarget);
      renderer.setClearColor(0x000000, 0);
      renderer.clearColor();
      renderer.render(photonScene, quadCamera);

      photonAccumMaterial.uniforms.uPrevPhotonTex.value = targets.readAirPhoton.texture;
      photonAccumMaterial.uniforms.uCurrPhotonTex.value = targets.airFrameTarget.texture;
      photonAccumMaterial.uniforms.uPhotonFrame.value = airPhotonFrameCount;

      renderer.setRenderTarget(targets.writeAirPhoton);
      renderer.render(photonAccumScene, quadCamera);
      targets.swapAirPhoton();
    }

    const nextSampleCount = sampleCount + samplesPerFrame;
    let finalHdrTexture = targets.writeAccum.textures[0];

    if (denoiseEnabled) {
      denoiseMaterial.uniforms.uGBufferTex.value = targets.writeAccum.textures[1];
      denoiseMaterial.uniforms.uAlbedoTex.value = targets.writeAccum.textures[2];
      denoiseMaterial.uniforms.uCamMatrix.value.copy(sceneManager.camera.matrixWorld);
      denoiseMaterial.uniforms.uTanHalfFov.value = Math.tan(THREE.MathUtils.degToRad(sceneManager.camera.fov * 0.5));
      denoiseMaterial.uniforms.uAspect.value = sceneManager.camera.aspect;
      denoiseMaterial.uniforms.uSampleCount.value = nextSampleCount;

      let srcTex = targets.writeAccum.textures[0];
      const dstTargets = [targets.denoiseA, targets.denoiseB, targets.denoiseA, targets.denoiseB];

      for (let i = 0; i < ATROUS_STEPS.length; i++) {
        denoiseMaterial.uniforms.uColorTex.value = srcTex;
        denoiseMaterial.uniforms.uPassIndex.value = i;
        denoiseMaterial.uniforms.uStepSize.value = ATROUS_STEPS[i];

        renderer.setRenderTarget(dstTargets[i]);
        renderer.render(denoiseScene, quadCamera);
        srcTex = dstTargets[i].texture;
      }

      finalHdrTexture = targets.denoiseB.texture;
    }

    displayMaterial.uniforms.uInputTexture.value = finalHdrTexture;
    displayMaterial.uniforms.uExtraTex.value = isDiffraction ? targets.readAirPhoton.texture : targets.blackTex;
    displayMaterial.uniforms.uHasExtraTex.value = isDiffraction ? 1 : 0;

    renderer.setRenderTarget(null);
    renderer.render(displayScene, quadCamera);

    targets.swapAccum();
  }

  return {
    setActiveScene,
    syncLaserUniforms,
    syncLensUniforms,
    updateResolution,
    renderFrame
  };
}