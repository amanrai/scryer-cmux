import { backendApiPath } from '../constants';

export function shellQuote(path: string) {
  return `'${path.replace(/'/g, `'\\''`)}'`;
}

export async function uploadFile(file: File, backendId?: string): Promise<string | null> {
  try {
    const response = await fetch(backendApiPath(backendId, '/upload'), {
      method: 'POST',
      headers: { 'x-smux-filename': encodeURIComponent(file.name) },
      body: file,
    });
    if (!response.ok) return null;
    const payload = await response.json() as { path?: string };
    return payload.path ?? null;
  } catch {
    return null;
  }
}
