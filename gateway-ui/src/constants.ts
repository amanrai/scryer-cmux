export const workspaceColors = [
  { name: 'Blue', value: '#5AA6F0' },
  { name: 'Amber', value: '#E8B65A' },
  { name: 'Green', value: '#6FCB7F' },
  { name: 'Cyan', value: '#4FC9D4' },
  { name: 'Purple', value: '#B47BE8' },
  { name: 'Coral', value: '#F0786E' },
  { name: 'Slate', value: '#8A93A3' },
] as const;

export const DEFAULT_FONT_SIZE = 10;
export const API_PORT = import.meta.env.VITE_SCRYER_CMUX_API_PORT ?? '43220';
export const API_HOST = window.location.hostname || '127.0.0.1';
export const API_BASE = `http://${API_HOST}:${API_PORT}`;
export const WS_BASE = `ws://${API_HOST}:${API_PORT}/api/terminal`;

export function backendApiPath(backendId: string | undefined, path: string) {
  if (!backendId) return `${API_BASE}/api${path}`;
  return `${API_BASE}/api/backends/${encodeURIComponent(backendId)}${path}`;
}

export function backendTerminalWsUrl(backendId: string | undefined, paneId: string) {
  const paneQuery = `paneId=${encodeURIComponent(paneId)}`;
  if (!backendId) return `${WS_BASE}?${paneQuery}`;
  return `ws://${API_HOST}:${API_PORT}/api/backends/${encodeURIComponent(backendId)}/terminal?${paneQuery}`;
}
