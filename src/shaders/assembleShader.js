import common from './chunks/common.glsl?raw';
import rng from './chunks/rng.glsl?raw';
import spectrum from './chunks/spectrum.glsl?raw';
import sampling from './chunks/sampling.glsl?raw';
import intersections from './chunks/intersections.glsl?raw';
import lenses from './chunks/lenses.glsl?raw';
import diffractionScene from './chunks/diffractionScene.glsl?raw';
import diffractionOptics from './chunks/diffractionOptics.glsl?raw';

const CHUNKS = {
  common,
  rng,
  spectrum,
  sampling,
  intersections,
  lenses,
  diffractionScene,
  diffractionOptics
};

export function assembleShader(source) {
  return source.replace(/^\s*\/\/#include\s+<(\w+)>\s*$/gm, (_, name) => {
    if (!(name in CHUNKS)) {
      throw new Error(`Shader chunk desconhecido: ${name}`);
    }
    return CHUNKS[name];
  });
}