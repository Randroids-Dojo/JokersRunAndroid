// Web reference for the selftest "diag" views (storm, wake, cloud field).
import { chromium } from '../../JokersRunArcade/node_modules/playwright-core/index.mjs';
const out = new URL('../artifacts/web/', import.meta.url).pathname;
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=metal', '--ignore-gpu-blocklist'] });
const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await ctx.newPage();
await page.goto('http://localhost:5190/?debug');
await page.waitForTimeout(2500);
const views = await page.evaluate(() => {
  const g = window.__joker.game;
  const c = g.fleet.carrierPos();
  const cl = g.env.clouds.clusters ? g.env.clouds.clusters[0] : null;
  return { c: [c.x, c.y, c.z], cl: cl ? [cl.center.x, cl.center.y, cl.center.z] : null };
});
console.log(JSON.stringify(views));
const [cx, cy, cz] = views.c;
const sets = {
  storm: [[cx, cy + 120, cz + 300], [-9000, 1800, 26000]],
  wake: [[cx + 260, cy + 140, cz + 1100], [cx, cy, cz + 400]],
};
if (views.cl) sets.clouds = [[views.cl[0], views.cl[1] + 300, views.cl[2] + 2600], views.cl];
for (const [name, [p, l]] of Object.entries(sets)) {
  await page.evaluate(([p, l]) => {
    window.__joker.game.env.lightningTimer = 1e9;
    window.__joker.game.rig.play((t, f) => { f.pos.set(...p); f.look.set(...l); f.up.set(0, 1, 0); f.fov = 60; });
  }, [p, l]);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: out + `diag_${name}.png` });
}
await browser.close();
