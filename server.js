const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const PORT = process.env.PORT || 3000;
const html = fs.readFileSync(path.join(__dirname, 'index.html'));
const gz = zlib.gzipSync(html, { level: 9 }); // siqilgan nusxa — telefonga kamroq yuklanadi

http.createServer((req, res) => {
  const headers = { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache', 'Vary': 'Accept-Encoding' };
  if (/\bgzip\b/.test(req.headers['accept-encoding'] || '')) {
    res.writeHead(200, { ...headers, 'Content-Encoding': 'gzip', 'Content-Length': gz.length });
    res.end(gz);
  } else {
    res.writeHead(200, headers);
    res.end(html);
  }
}).listen(PORT, '0.0.0.0', () => {
  console.log('YOLDA running on port ' + PORT);
});
