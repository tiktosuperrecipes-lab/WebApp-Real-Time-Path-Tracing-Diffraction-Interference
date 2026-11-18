import * as THREE from 'three';

function createAccumMRT(width, height, type) {
  return new THREE.WebGLRenderTarget(width, height, {
    count: 2,
    type,
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

export function createRenderTargets(width, height, accumType, worldAtlasSize = 1024) {
  const blackTex = new THREE.DataTexture(new Uint8Array([0, 0, 0, 255]), 1, 1, THREE.RGBAFormat);
  blackTex.needsUpdate = true;

  const state = {
    readAccum: createAccumMRT(width, height, accumType),
    writeAccum: createAccumMRT(width, height, accumType),
    denoiseA: createHalfTarget(width, height, THREE.LinearFilter),
    denoiseB: createHalfTarget(width, height, THREE.LinearFilter),
    airFrameTarget: createHalfTarget(width, height, THREE.NearestFilter),
    readAirPhoton: createHalfTarget(width, height, THREE.LinearFilter),
    writeAirPhoton: createHalfTarget(width, height, THREE.LinearFilter),
    worldPhotonFrameTarget: createHalfTarget(worldAtlasSize, worldAtlasSize, THREE.NearestFilter),
    readWorldPhoton: createHalfTarget(worldAtlasSize, worldAtlasSize, THREE.LinearFilter),
    writeWorldPhoton: createHalfTarget(worldAtlasSize, worldAtlasSize, THREE.LinearFilter),
    blackTex,

    swapAccum() {
      const tmp = state.readAccum;
      state.readAccum = state.writeAccum;
      state.writeAccum = tmp;
    },
    swapAirPhoton() {
      const tmp = state.readAirPhoton;
      state.readAirPhoton = state.writeAirPhoton;
      state.writeAirPhoton = tmp;
    },
    swapWorldPhoton() {
      const tmp = state.readWorldPhoton;
      state.readWorldPhoton = state.writeWorldPhoton;
      state.writeWorldPhoton = tmp;
    },
    resizeScreen(w, h) {
      state.readAccum.setSize(w, h);
      state.writeAccum.setSize(w, h);
      state.denoiseA.setSize(w, h);
      state.denoiseB.setSize(w, h);
      state.airFrameTarget.setSize(w, h);
      state.readAirPhoton.setSize(w, h);
      state.writeAirPhoton.setSize(w, h);
    }
  };

  return state;
}