import { API_BASE } from '../constants';

export function shellQuote(value: string) {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

export async function uploadFile(file: File): Promise<string | null> {
  try {
    const response = await fetch(`${API_BASE}/api/upload`, {
      method: 'POST',
      headers: {
        'content-type': file.type || 'application/octet-stream',
        'x-smux-filename': encodeURIComponent(file.name),
      },
      body: file,
    });
    if (!response.ok) return null;
    const data = await response.json();
    return typeof data.path === 'string' ? data.path : null;
  } catch {
    return null;
  }
}
