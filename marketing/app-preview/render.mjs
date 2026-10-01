import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const dir = path.dirname(fileURLToPath(import.meta.url));
const TL = createRequire(import.meta.url)('./timeline.js');
const out = path.join(dir, 'out');
mkdirSync(out, { recursive: true });

const args = process.argv.slice(2);
const variantIdx = args.indexOf('--variant');
const variant = variantIdx >= 0 ? args[variantIdx + 1] : 'dark';
TL.useVariant(variant);
const suffix = variant === 'dark' ? '' : '-' + variant;
const stillsIdx = args.indexOf('--stills');
const stills = stillsIdx >= 0 ? args[stillsIdx + 1].split(',').map(Number) : null;

const browser = await chromium.launch({ channel: 'chrome', args: ['--allow-file-access-from-files', '--force-color-profile=srgb'] });
const page = await browser.newPage({ viewport: { width: 886, height: 1920 }, deviceScaleFactor: 1 });
page.on('pageerror', e => console.error('page error:', e.message));
await page.goto(pathToFileURL(path.join(dir, 'index.html')).href + '?variant=' + variant);

if (stills) {
  for (const t of stills) {
    await page.evaluate(t => window.renderFrame(t), t);
    const file = path.join(out, `still${suffix}_${t.toFixed(2)}.png`);
    await page.screenshot({ path: file });
    console.log(file);
  }
} else {
  const frames = Math.round(TL.duration * TL.fps);
  const video = path.join(out, `picture${suffix}.mp4`);
  const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', String(TL.fps), '-i', '-',
    '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p',
    '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '12', video], { stdio: ['pipe', 'inherit', 'inherit'] });
  const started = Date.now();
  for (let f = 0; f < frames; f++) {
    await page.evaluate(t => window.renderFrame(t), f / TL.fps);
    const buf = await page.screenshot({ type: 'png' });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (f % 60 === 0) console.log(`frame ${f}/${frames} · ${((Date.now() - started) / 1000).toFixed(0)} s`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
  console.log(video);
}
await browser.close();
