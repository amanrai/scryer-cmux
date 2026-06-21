import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const repoRoot = path.resolve(__dirname, '..');
export const port = Number(process.env.SCRYER_CMUX_API_PORT ?? 43220);
export const shell = process.env.SHELL || (process.platform === 'win32' ? 'powershell.exe' : '/bin/zsh');
export const shellArgs = process.platform === 'win32' ? [] : ['-il'];
export const statePath = path.join(repoRoot, '.smux-state.json');
export const uploadsDir = path.join(os.tmpdir(), 'smux-uploads');
export const maxUploadBytes = 50 * 1024 * 1024;
export const maxReplayBytes = Number(process.env.SCRYER_CMUX_MAX_REPLAY_BYTES ?? 10 * 1024);
