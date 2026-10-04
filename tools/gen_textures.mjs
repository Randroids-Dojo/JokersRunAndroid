// Render textures and launcher icons with the same canvas code as the web build.
// node tools/gen_textures.mjs   (uses the web project's playwright-core + installed Chrome)
import { chromium } from '../../JokersRunArcade/node_modules/playwright-core/index.mjs';
import { writeFileSync } from 'node:fs';

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage();
await page.setContent('<html><head><link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:ital,wght@1,700&display=block" rel="stylesheet"></head><body></body></html>');
await page.waitForTimeout(1200);
const out = await page.evaluate(() => {
  const mulberry32 = (seed) => { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
  const make = (w, h, draw) => { const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h); return c.toDataURL('image/png'); };
  const res = {};
  res.cloud = make(256, 256, (ctx) => {
    const rng = mulberry32(3);
    for (let i = 0; i < 26; i++) {
      const a = rng() * Math.PI * 2, r = rng() * 256 * 0.22;
      const x = 128 + Math.cos(a) * r, y = 128 + Math.sin(a) * r * 0.7, rad = 256 * (0.14 + rng() * 0.16);
      const g = ctx.createRadialGradient(x, y - rad * 0.25, 0, x, y, rad);
      const light = Math.round(200 + 55 * (1 - y / 256));
      g.addColorStop(0, `rgba(${light},${light},${light},0.55)`);
      g.addColorStop(0.6, `rgba(${light - 40},${light - 40},${light - 40},0.25)`);
      g.addColorStop(1, 'rgba(120,120,120,0)');
      ctx.fillStyle = g; ctx.fillRect(0, 0, 256, 256);
    }
  });
  res.wake = make(64, 256, (ctx) => {
    const grd = ctx.createLinearGradient(0, 0, 0, 256);
    grd.addColorStop(0, 'rgba(255,255,255,0.95)'); grd.addColorStop(0.3, 'rgba(255,255,255,0.5)'); grd.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = grd; ctx.fillRect(0, 0, 64, 256);
    const side = ctx.createLinearGradient(0, 0, 64, 0);
    side.addColorStop(0, 'rgba(0,0,0,1)'); side.addColorStop(0.3, 'rgba(0,0,0,0)'); side.addColorStop(0.7, 'rgba(0,0,0,0)'); side.addColorStop(1, 'rgba(0,0,0,1)');
    ctx.globalCompositeOperation = 'destination-out'; ctx.fillStyle = side; ctx.fillRect(0, 0, 64, 256);
  });
  res.rain = make(128, 256, (ctx) => {
    const rng = mulberry32(11);
    for (let i = 0; i < 120; i++) {
      const x = rng() * 128; const g = ctx.createLinearGradient(0, 0, 0, 256); const a = 0.05 + rng() * 0.12;
      g.addColorStop(0, `rgba(40,46,56,${a * 2})`); g.addColorStop(0.7, `rgba(40,46,56,${a})`); g.addColorStop(1, 'rgba(40,46,56,0)');
      ctx.fillStyle = g; ctx.fillRect(x, 0, 2 + rng() * 6, 256);
    }
    const side = ctx.createLinearGradient(0, 0, 128, 0);
    side.addColorStop(0, 'rgba(0,0,0,1)'); side.addColorStop(0.25, 'rgba(0,0,0,0)'); side.addColorStop(0.75, 'rgba(0,0,0,0)'); side.addColorStop(1, 'rgba(0,0,0,1)');
    ctx.globalCompositeOperation = 'destination-out'; ctx.fillStyle = side; ctx.fillRect(0, 0, 128, 256);
  });
  res.soft = make(64, 64, (ctx) => {
    const img = ctx.createImageData(64, 64);
    for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
      const dx = (x + 0.5) / 32 - 1, dy = (y + 0.5) / 32 - 1, r = Math.min(1, dx * dx + dy * dy);
      const a = (1 - r) * (1 - r); const i = (y * 64 + x) * 4;
      img.data[i] = img.data[i + 1] = img.data[i + 2] = 255; img.data[i + 3] = Math.round(a * 255);
    }
    ctx.putImageData(img, 0, 0);
  });
  res.disc = make(256, 256, (ctx) => {
    const g = ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
    g.addColorStop(0, 'rgba(255,220,120,0.0)'); g.addColorStop(0.75, 'rgba(255,210,90,0.06)'); g.addColorStop(0.97, 'rgba(255,200,80,0.35)'); g.addColorStop(1, 'rgba(255,200,80,0)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, 256, 256);
  });
  const jr = (ctx, s, bg) => {
    if (bg) { const g = ctx.createRadialGradient(s * 0.3, s * 0.25, 0, s * 0.5, s * 0.5, s * 0.75); g.addColorStop(0, '#1a2633'); g.addColorStop(1, '#05080c'); ctx.fillStyle = g; ctx.fillRect(0, 0, s, s); }
    ctx.save(); ctx.translate(s * 0.5, s * 0.5);
    ctx.font = `italic 700 ${s * 0.36}px "Chakra Petch"`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillStyle = 'rgba(192,40,45,0.95)'; ctx.fillText('JR', s * 0.018, s * 0.02 + s * 0.018);
    ctx.fillStyle = '#f5f2ea'; ctx.fillText('JR', 0, s * 0.02);
    ctx.fillStyle = '#d3242b'; ctx.translate(s * 0.2, -s * 0.2); ctx.rotate(Math.PI / 4); ctx.fillRect(-s * 0.035, -s * 0.035, s * 0.07, s * 0.07);
    ctx.restore();
  };
  res.icon_fg = make(432, 432, (ctx) => jr(ctx, 432, false));
  res.icon_bg = make(432, 432, (ctx) => { const g = ctx.createRadialGradient(130, 108, 0, 216, 216, 320); g.addColorStop(0, '#1a2633'); g.addColorStop(1, '#05080c'); ctx.fillStyle = g; ctx.fillRect(0, 0, 432, 432); });
  res.icon_192 = make(192, 192, (ctx) => jr(ctx, 192, true));
  res.icon_512 = make(512, 512, (ctx) => jr(ctx, 512, true));
  return res;
});
const dest = { icon_fg: 'assets/icon_foreground.png', icon_bg: 'assets/icon_background.png', icon_192: 'assets/icon_192.png', icon_512: 'icon.png' };
for (const [k, v] of Object.entries(out)) {
  const path = dest[k] ?? `assets/tex/${k}.png`;
  writeFileSync(new URL('../' + path, import.meta.url), Buffer.from(v.split(',')[1], 'base64'));
  console.log('wrote', path);
}
await browser.close();
