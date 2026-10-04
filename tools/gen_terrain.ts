// Bake the web game's terrain height field so the native port flies over identical land.
// npx tsx tools/gen_terrain.ts
import { writeFileSync } from 'node:fs';
import { LAND, rawHeight, BRIDGE_X, BRIDGE_DECK_Y, STACKS } from '../../JokersRunArcade/src/terrain';

const nx = Math.round((LAND.x1 - LAND.x0) / LAND.cell) + 1;
const nz = Math.round((LAND.z1 - LAND.z0) / LAND.cell) + 1;
const h = new Float32Array(nx * nz);
for (let iz = 0; iz < nz; iz++) for (let ix = 0; ix < nx; ix++) h[iz * nx + ix] = rawHeight(LAND.x0 + ix * LAND.cell, LAND.z0 + iz * LAND.cell);
writeFileSync('assets/data/heights.bin', Buffer.from(h.buffer));
// 8-bit shoreline map for the ocean foam (same encoding as the web ocean shader).
const h8 = new Uint8Array(h.length);
for (let i = 0; i < h.length; i++) h8[i] = Math.max(0, Math.min(255, Math.round((h[i] + 40) * 2)));
writeFileSync('assets/data/heights8.bin', Buffer.from(h8.buffer));
writeFileSync(
  'assets/data/terrain.json',
  JSON.stringify({ x0: LAND.x0, z0: LAND.z0, cell: LAND.cell, nx, nz, bridgeX: BRIDGE_X, bridgeDeckY: BRIDGE_DECK_Y, stacks: STACKS }, null, 1),
);
let min = Infinity, max = -Infinity;
for (const v of h) { min = Math.min(min, v); max = Math.max(max, v); }
console.log({ nx, nz, min: min.toFixed(1), max: max.toFixed(1), bridgeX: BRIDGE_X });
