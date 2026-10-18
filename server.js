// YO'LDA — kichik, bog'liqliksiz (dependency-free) server: ilova + o'rnatish (PWA) fayllarini beradi.
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const PORT = process.env.PORT || 3000;
const NO_CACHE = 'no-cache';
const DAY = 'public, max-age=86400';
// URL → fayl. Ro'yxatda bo'lmagan "sahifa" manzillari ilovaning o'zini (index.html) oladi.
const ROUTES = {
  '/': ['index.html', 'text/html; charset=utf-8', NO_CACHE],
  '/manifest.webmanifest': ['manifest.webmanifest', 'application/manifest+json; charset=utf-8', NO_CACHE],
  '/sw.js': ['sw.js', 'application/javascript; charset=utf-8', NO_CACHE, { 'Service-Worker-Allowed': '/' }],
  '/icon-192.png': ['icon-192.png', 'image/png', DAY],
  '/icon-512.png': ['icon-512.png', 'image/png', DAY],
  '/icon-maskable-512.png': ['icon-maskable-512.png', 'image/png', DAY],
  '/apple-touch-icon.png': ['apple-touch-icon.png', 'image/png', DAY],
  '/favicon.ico': ['icon-192.png', 'image/png', DAY],
};
const TEXTUAL = /^(text\/|application\/(javascript|manifest\+json))/;

const files = {};
for (const [url, [file, type, cache, extra]] of Object.entries(ROUTES)) {
  try {
    const body = fs.readFileSync(path.join(__dirname, file));
    files[url] = { body, gz: TEXTUAL.test(type) ? zlib.gzipSync(body, { level: 9 }) : null, headers: { 'Content-Type': type, 'Cache-Control': cache, 'Vary': 'Accept-Encoding', ...(extra || {}) } };
  } catch (e) { console.error('Fayl topilmadi, o\'tkazib yuborildi:', file); }
}

http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, { Allow: 'GET, HEAD' }); return res.end(); }
  const pathname = decodeURIComponent((req.url || '/').split('?')[0]);
  let entry = files[pathname];
  if (!entry) {
    // fayl kengaytmasi bor, lekin ro'yxatda yo'q (masalan /abc.js) — 404; qolgani — ilova (index.html)
    if (/\.[a-z0-9]{2,5}$/i.test(pathname)) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); return res.end('Topilmadi'); }
    entry = files['/'];
  }
  if (!entry) { res.writeHead(500); return res.end('index.html topilmadi'); }
  const useGzip = entry.gz && /\bgzip\b/.test(req.headers['accept-encoding'] || '');
  const body = useGzip ? entry.gz : entry.body;
  res.writeHead(200, { ...entry.headers, ...(useGzip ? { 'Content-Encoding': 'gzip' } : {}), 'Content-Length': body.length });
  res.end(req.method === 'HEAD' ? undefined : body);
}).listen(PORT, '0.0.0.0', () => {
  console.log('YOLDA running on port ' + PORT);
});
