uint pcgHash(inout uint state) {
  state = state * 747796405u + 2891336453u;
  uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

float rand(inout uint state) {
  return float(pcgHash(state) >> 8u) * (1.0 / 16777216.0);
}