// Reference screenshots of the web build at the phone viewport the Android port targets.
// Usage: node tools/web_shots.mjs   (web dev server on :5190)
import { chromium } from '../../JokersRunArcade/node_modules/playwright-core/index.mjs';

const base = process.env.URL ?? 'http://localhost:5190/';
const out = new URL('../artifacts/web/', import.meta.url).pathname;
const W = 844;
const H = 390;
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=metal', '--ignore-gpu-blocklist'] });
const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('pageerror', e.message));
await page.goto(base + '?debug');
await page.waitForTimeout(2500);
await page.screenshot({ path: out + 'title.png' });
for (const cp of ['launch', 'training', 'scouts', 'chase', 'ace', 'final']) {
  await page.evaluate(`__joker.god(true); __joker.start('${cp}')`);
  await page.waitForTimeout(cp === 'launch' ? 2500 : 8000);
  await page.screenshot({ path: out + `cp_${cp}.png` });
  if (cp === 'launch') {
    await page.evaluate(`__joker.bot(true)`);
    await page.waitForTimeout(9000);
    await page.screenshot({ path: out + `cp_launch_fly.png` });
    await page.evaluate(`__joker.bot(false)`);
  }
}
await browser.close();
console.log('done');
