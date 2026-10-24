// Loads the live site in headless Chrome as a phone and reports whether the
// page is cross-origin isolated (needed for smooth multi-threaded
// rendering), which app files loaded, console errors and scroll smoothness.
const { chromium } = require('playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome' });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2.75,
    userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36' });
  const p = await ctx.newPage();
  p.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') console.log('console.' + m.type() + ':', m.text().slice(0, 300)); });
  p.on('pageerror', e => console.log('pageerror:', String(e).slice(0, 300)));
  p.on('response', r => { const u = r.url(); if (/\.(wasm|mjs|js)(\?|$)/.test(u) || r.status() >= 400) console.log('resp', r.status(), u.slice(0, 120)); });
  await p.goto('https://izmirimexpress.com/', { waitUntil: 'networkidle', timeout: 90000 });
  await p.waitForTimeout(8000);
  console.log('state', JSON.stringify(await p.evaluate(() => ({
    isolated: self.crossOriginIsolated, sab: typeof SharedArrayBuffer, href: location.href,
    zoom: window.izmirimZoom, inner: innerWidth, screen: screen.width, dpr: devicePixelRatio,
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
  await b.close();
})();
