// Lightweight Express server for the React frontend that also proxies API requests
// This replaces the previous nginx-based reverse proxy approach.

const express = require('express');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();
const PORT = process.env.PORT || 3000; // frontend port

// Backend base URL (internal service/hostname). Example: http://backend:3001
const BACKEND_API_URL = (process.env.BACKEND_API_URL || 'http://backend:3001').replace(/\/$/, '');

console.log(`[frontend] Starting frontend server on port ${PORT}`);
console.log(`[frontend] Proxy target BACKEND_API_URL=${BACKEND_API_URL}`);

// Health endpoint (frontend self) — still routed through backend for consolidated status
app.get('/health', createProxyMiddleware({
  target: BACKEND_API_URL,
  changeOrigin: true,
  pathRewrite: { '^/health': '/health' },
  logLevel: 'warn',
  onProxyRes: (proxyRes, req, res) => {
    const chunks = [];
    proxyRes.on('data', c => chunks.push(c));
    proxyRes.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      console.log(`[frontend<-backend] HEALTH ${req.method} ${req.originalUrl} -> ${proxyRes.statusCode} body: ${raw}`);
    });
  }
}));

// Proxy API routes
app.use('/api', createProxyMiddleware({
  target: BACKEND_API_URL,
  changeOrigin: true,
  logLevel: 'warn',
  proxyTimeout: 300000,
  onProxyReq: (proxyReq, req) => {
    console.log(`[frontend->backend] ${req.method} ${req.originalUrl}`);
  },
  onProxyRes: (proxyRes, req, res) => {
    const chunks = [];
    proxyRes.on('data', c => chunks.push(c));
    proxyRes.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      console.log(`[frontend<-backend] ${req.method} ${req.originalUrl} -> ${proxyRes.statusCode} body: ${raw}`);
    });
  },
  onError: (err, req, res) => {
    console.error('[frontend proxy] Error:', err.message);
    if (!res.headersSent) {
      res.status(502).json({ error: 'Frontend proxy failure', message: err.message });
    }
  }
}));

// Serve static React build
const buildPath = path.join(__dirname, '..', 'build');
app.use(express.static(buildPath));

// SPA fallback
app.get('*', (req, res) => {
  res.sendFile(path.join(buildPath, 'index.html'));
});

app.listen(PORT, () => {
  console.log(`[frontend] Server listening on port ${PORT}`);
});
