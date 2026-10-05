// Copies the radio voice clips and their manifest from the web build, which generates them
// (JokersRunArcade/scripts/voice/generate.py): node tools/voice_sync.mjs
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync } from 'node:fs';

const web = new URL('../../JokersRunArcade/', import.meta.url).pathname;
const root = new URL('../', import.meta.url).pathname;
const manifest = JSON.parse(readFileSync(web + 'src/voice-manifest.json', 'utf8'));
const files = new Set(Object.values(manifest).map((c) => c.file.replace(/^voice\//, '')));
mkdirSync(root + 'assets/voice', { recursive: true });
for (const f of files) {
  if (!existsSync(root + 'assets/voice/' + f)) copyFileSync(web + 'public/voice/' + f, root + 'assets/voice/' + f);
}
for (const f of readdirSync(root + 'assets/voice')) {
  if (!files.has(f.replace(/\.import$/, ''))) rmSync(root + 'assets/voice/' + f);
}
copyFileSync(web + 'src/voice-manifest.json', root + 'assets/data/voice.json');
console.log(`${files.size} clips in assets/voice, manifest in assets/data/voice.json`);
