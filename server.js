const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = 3000;
const WEB_DIR = path.join(__dirname, "web");

const MIME = {
  ".html": "text/html",
  ".js":   "application/javascript",
  ".wasm": "application/wasm",
  ".data": "application/octet-stream",
  ".css":  "text/css",
  ".png":  "image/png",
  ".ico":  "image/x-icon",
};

const server = http.createServer((req, res) => {
  let filePath = path.join(WEB_DIR, req.url === "/" ? "index.html" : req.url);

  // Prevent path traversal
  if (!filePath.startsWith(WEB_DIR)) {
    res.writeHead(403); res.end(); return;
  }

  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end("Not found"); return; }
    const ext = path.extname(filePath);
    res.writeHead(200, {
      "Content-Type": MIME[ext] || "application/octet-stream",
      // Required for SharedArrayBuffer (pthreads in Emscripten)
      "Cross-Origin-Opener-Policy":   "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`Serving web/ at http://localhost:${PORT}`);
});
