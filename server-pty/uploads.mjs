import { randomUUID } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { maxUploadBytes, uploadsDir } from './config.mjs';
import { json, readRawBody } from './http-utils.mjs';

function sanitizeUploadName(raw) {
  let name = 'file';
  try {
    name = decodeURIComponent(String(raw ?? ''));
  } catch {
    name = String(raw ?? '');
  }
  name = path.basename(name).replace(/[^\w.-]+/g, '_').slice(0, 120);
  return name || 'file';
}

export async function handleUpload(req, res) {
  try {
    const data = await readRawBody(req, maxUploadBytes);
    if (!data.length) {
      json(res, 400, { error: 'empty upload' });
      return;
    }
    mkdirSync(uploadsDir, { recursive: true });
    const fileName = `${Date.now().toString(36)}-${randomUUID().slice(0, 8)}-${sanitizeUploadName(req.headers['x-smux-filename'])}`;
    const filePath = path.join(uploadsDir, fileName);
    writeFileSync(filePath, data);
    json(res, 200, { path: filePath });
  } catch (error) {
    json(res, 413, { error: error instanceof Error ? error.message : 'upload failed' });
  }
}
