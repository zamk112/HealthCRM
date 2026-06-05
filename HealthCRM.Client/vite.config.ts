import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import { readFileSync, existsSync } from 'node:fs';
import os from 'node:os';
import https from 'node:https';

const certName = 'HealthCRM.Client';
const certFolder = path.join(os.homedir(), 'Workspaces', 'Certs', 'dotnet');
const certPath = path.join(certFolder, `${certName}.pem`);
const keyPath = path.join(certFolder, `${certName}.key`);

if (!existsSync(certPath) || !existsSync(keyPath)) {
  throw new Error('Certificate not found.');
}

const target = `https://localhost:7186`;

export default defineConfig({
  plugins: [react()],
  server: {
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
          ca: readFileSync(certPath)
        })
      }
    }
  }
})
