// Passenger startup file for cPanel > "Setup Node.js App" (shared hosting, no root).
// Set "Application startup file" to: app.js  and "Application root" to the folder holding this file.
// This file lives NEXT TO the built OpenWA (dist/, node_modules/, dashboard/dist).
//
// Passenger tells the app which socket/port to use through process.env.PORT or by patching listen();
// OpenWA reads PORT, so we just make sure the working directory and env are right, then load it.
'use strict';
const path = require('path');
process.chdir(__dirname);
process.env.NODE_ENV = process.env.NODE_ENV || 'production';
// The WhatsApp engine must be Baileys on shared hosting (no Chromium available).
process.env.ENGINE_TYPE = process.env.ENGINE_TYPE || 'baileys';
// Load .env manually if cPanel's UI did not (the UI env vars take precedence if set).
try {
  const fs = require('fs');
  const envFile = path.join(__dirname, '.env');
  if (fs.existsSync(envFile)) {
    for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
      if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
    }
  }
} catch (e) { console.error('env load failed', e); }

require('./dist/main');
