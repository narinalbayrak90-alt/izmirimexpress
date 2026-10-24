// İzmirim Express service worker.
//
// Its only job is to make the site installable as an app (Android/Chrome
// "Install", Samsung Internet, desktop Chrome/Edge): browsers want a
// service worker with a fetch handler before they offer to install.
// Nothing is cached — every request goes to the network as usual, so a
// new deploy is picked up on the next load.
//
// Served from /app/sw.js with a `Service-Worker-Allowed: /` header (see
// tool/build_web.sh) so it can control the whole site, where the app
// lives at `/`.

// OneSignal's push handling (browser notifications for order updates),
// in this same worker because a site can only have one per scope. If the
// CDN can't be reached the worker still installs, just without push.
try {
  importScripts('https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js');
} catch (e) {
  // Push stays off until the next successful install.
}

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.mode !== 'navigate') return;
  // Page loads only, and never the admin panel's; everything else goes
  // straight through without the worker.
  if (new URL(request.url).pathname.startsWith('/admin')) return;
  event.respondWith(
    fetch(request).catch(() => new Response(
      '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">' +
      '<body style="font-family:sans-serif;text-align:center;padding:48px 16px">' +
      '<h2>İnternet bağlantısı yok</h2><p>Bağlantınız gelince sayfayı yenileyin.</p></body>',
      { headers: { 'Content-Type': 'text/html; charset=utf-8' } },
    )),
  );
});
