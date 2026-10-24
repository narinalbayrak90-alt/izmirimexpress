// Loads the live site in headless Chrome as a phone and reports whether the
// page is cross-origin isolated (needed for smooth multi-threaded
// rendering), which app files loaded, console errors and scroll smoothness.
const { chromium } = require('playwright-core');
const UA = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';
(async () => {
  const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome' });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2.75,
    userAgent: UA });
  const p = await ctx.newPage();
  p.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') console.log('console.' + m.type() + ':', m.text().slice(0, 300)); });
  p.on('pageerror', e => console.log('pageerror:', String(e).slice(0, 300)));
  p.on('response', r => { const u = r.url(); if (/\.(wasm|mjs|js)(\?|$)/.test(u) || r.status() >= 400) console.log('resp', r.status(), u.slice(0, 120)); });
  await p.goto('https://izmirimexpress.com/', { waitUntil: 'networkidle', timeout: 90000 });
  await p.waitForTimeout(8000);
  console.log('state', JSON.stringify(await p.evaluate(() => ({
    isolated: self.crossOriginIsolated, sab: typeof SharedArrayBuffer, href: location.href,
    zoom: window.izmirimZoom ? window.izmirimZoom() : 'missing', inner: innerWidth, screen: screen.width, dpr: devicePixelRatio,
    view: !!document.querySelector('flutter-view'),
  }))));
  const cdp = await ctx.newCDPSession(p);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await p.evaluate(() => { window._f = []; let last = performance.now(); const tick = t => { window._f.push(t - last); last = t; if (window._f.length < 400) requestAnimationFrame(tick); }; requestAnimationFrame(tick); });
  for (let i = 0; i < 4; i++) await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: i % 2 ? 500 : -500, speed: 1200, gestureSourceType: 'touch' });
  const f = await p.evaluate(() => window._f.slice(5)); f.sort((a, c) => a - c);
  const n = f.length;
  console.log('scroll frames', n, 'avg', (f.reduce((a, c) => a + c, 0) / n).toFixed(1), 'p90', f[Math.floor(n * .9)].toFixed(1), 'slow', f.filter(x => x > 33).length);
  await p.screenshot({ path: 'live.png' });
  // Android with the page zoomed to 125% (what a larger system font size
  // does): the app should look the same as above.
  const z = 1.25;
  const zc = await b.newContext({ viewport: { width: Math.round(390 / z), height: Math.round(844 / z) }, screen: { width: 390, height: 844 },
    isMobile: true, hasTouch: true, deviceScaleFactor: 2.75 * z, userAgent: UA });
  const zp = await zc.newPage();
  await zp.goto('https://izmirimexpress.com/', { waitUntil: 'networkidle', timeout: 90000 });
  await zp.waitForTimeout(8000);
  console.log('zoomed', JSON.stringify(await zp.evaluate(() => ({ zoom: window.izmirimZoom ? window.izmirimZoom() : 'missing', inner: innerWidth, dpr: devicePixelRatio }))));
  await zp.screenshot({ path: 'live-zoom125.png' });
  await b.close();
})();
