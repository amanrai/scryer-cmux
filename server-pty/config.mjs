import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const repoRoot = path.resolve(__dirname, '..');
export const port = Number(process.env.AMUX_PTY_API_PORT ?? process.env.SCRYER_PTY_API_PORT ?? 43222);
export const shell = process.env.SHELL || (process.platform === 'win32' ? 'powershell.exe' : '/bin/zsh');
export const shellArgs = process.platform === 'win32' ? [] : ['-il'];
export const statePath = path.join(repoRoot, '.amux-pty-state.json');
export const gatewayConfigPath = path.join(repoRoot, '.amux-pty-config.json');
export const uploadsDir = path.join(os.tmpdir(), 'amux-pty-uploads');
export const maxUploadBytes = 50 * 1024 * 1024;
export const maxReplayBytes = Number(process.env.AMUX_PTY_MAX_REPLAY_BYTES ?? process.env.SCRYER_CMUX_MAX_REPLAY_BYTES ?? 100 * 1024);
export const pmUrl = (process.env.SCRYER_PM_URL ?? 'http://100.105.192.98:43210').replace(/\/$/, '');
