import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import { readFileSync, existsSync } from 'node:fs';
import os from 'node:os';
import https from 'node:https';

const target = `https://localhost:7186`;

export default defineConfig(({ command }) => {
  const certName = 'HealthCRM.Client';
  const certFolder = path.join(os.homedir(), 'Workspaces', 'Certs', 'dotnet');
  const certPath = path.join(certFolder, `${certName}.pem`);
  const keyPath = path.join(certFolder, `${certName}.key`);

  if (command === 'serve' && (!existsSync(certPath) || !existsSync(keyPath))) {
    throw new Error('Certificate not found.');
  }

  return {
    plugins: [react()],
    server: command === 'serve' ? {
      port: 5173,
      https: {
        key: readFileSync(keyPath),
        cert: readFileSync(certPath)
      },
      proxy: {
        '^/weatherforecast': {
          target: target,
          secure: true,
          agent: new https.Agent({
            ca: readFileSync(certPath),
            keepAlive: true,
            keepAliveMsecs: 10000,
            timeout: 25000,
            maxSockets: 5,
            maxFreeSockets: 5
          }),
          xfwd: true
        }
      }
    } : undefined
  }
});
