export const port = Number(process.env.AMUX_GATEWAY_PORT ?? process.env.SCRYER_AMUX_GATEWAY_PORT ?? 43223);

const defaultBackends = [
  {
    id: 'local',
    label: 'Local PTY',
    kind: 'pty',
    baseUrl: process.env.AMUX_LOCAL_PTY_URL ?? 'http://127.0.0.1:43222',
    transport: 'local',
    capabilities: ['terminal', 'state', 'upload', 'pm-proxy'],
  },
];

export function loadBackends() {
  const raw = process.env.AMUX_BACKENDS_JSON;
  if (!raw) return defaultBackends;
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error('AMUX_BACKENDS_JSON must be an array');
    return parsed.map((backend) => ({
      id: String(backend.id),
      label: String(backend.label ?? backend.id),
      kind: String(backend.kind ?? 'pty'),
      baseUrl: String(backend.baseUrl ?? '').replace(/\/$/, ''),
      transport: String(backend.transport ?? 'tailnet'),
      capabilities: Array.isArray(backend.capabilities) ? backend.capabilities.map(String) : ['terminal'],
      hostInfo: backend.hostInfo && typeof backend.hostInfo === 'object' ? backend.hostInfo : undefined,
    })).filter((backend) => backend.id && backend.baseUrl);
  } catch (error) {
    console.warn(`Invalid AMUX_BACKENDS_JSON: ${error instanceof Error ? error.message : String(error)}`);
    return defaultBackends;
  }
}
