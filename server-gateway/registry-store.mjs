import fs from 'node:fs';
import path from 'node:path';
import { repoRoot } from './config.mjs';

const storePath = path.join(repoRoot, '.amux-gateway-backends.json');
const staleAfterMs = Number(process.env.AMUX_BACKEND_STALE_AFTER_MS ?? 30_000);
const offlineAfterMs = Number(process.env.AMUX_BACKEND_OFFLINE_AFTER_MS ?? 90_000);

function normalizeBackend(backend, source = 'registered') {
  const id = String(backend.id ?? '').trim();
  const baseUrl = String(backend.baseUrl ?? backend.url ?? '').replace(/\/$/, '');
  if (!id || !baseUrl) return null;
  return {
    id,
    label: String(backend.label ?? backend.name ?? id),
    kind: String(backend.kind ?? 'pty'),
    baseUrl,
    transport: String(backend.transport ?? 'tailnet'),
    capabilities: Array.isArray(backend.capabilities) ? backend.capabilities.map(String) : ['terminal'],
    hostInfo: backend.hostInfo && typeof backend.hostInfo === 'object' ? backend.hostInfo : undefined,
    registeredAt: backend.registeredAt ?? new Date().toISOString(),
    lastSeenAt: backend.lastSeenAt,
    source,
  };
}

function readStoredBackends() {
  try {
    if (!fs.existsSync(storePath)) return [];
    const parsed = JSON.parse(fs.readFileSync(storePath, 'utf8'));
    if (!Array.isArray(parsed.backends)) return [];
    return parsed.backends.map((backend) => normalizeBackend(backend)).filter(Boolean);
  } catch (error) {
    console.warn(`Could not read gateway backend registry: ${error instanceof Error ? error.message : String(error)}`);
    return [];
  }
}

function writeStoredBackends(backends) {
  fs.writeFileSync(storePath, `${JSON.stringify({ backends }, null, 2)}\n`);
}

function computeStatus(backend) {
  if (!backend.lastSeenAt) return backend.source === 'static' ? 'unknown' : 'offline';
  const age = Date.now() - Date.parse(backend.lastSeenAt);
  if (!Number.isFinite(age)) return 'unknown';
  if (age > offlineAfterMs) return 'offline';
  if (age > staleAfterMs) return 'stale';
  return 'online';
}

export function createRegistry(staticBackends) {
  const staticIds = new Set(staticBackends.map((backend) => String(backend.id ?? '').trim()).filter(Boolean));
  let registeredBackends = readStoredBackends().filter((backend) => !staticIds.has(backend.id));

  function allBackends() {
    const map = new Map();
    for (const backend of staticBackends.map((entry) => normalizeBackend(entry, 'static')).filter(Boolean)) {
      map.set(backend.id, backend);
    }
    for (const backend of registeredBackends) map.set(backend.id, backend);
    return [...map.values()];
  }

  function list() {
    return allBackends().map((backend) => ({ ...backend, status: computeStatus(backend) }));
  }

  function find(id = 'local') {
    return allBackends().find((backend) => backend.id === id);
  }

  function register(payload) {
    if (staticIds.has(String(payload.id ?? '').trim())) throw new Error('backend id is reserved by static gateway config');
    const now = new Date().toISOString();
    const existing = registeredBackends.find((backend) => backend.id === payload.id);
    const normalized = normalizeBackend({ ...existing, ...payload, registeredAt: existing?.registeredAt ?? now, lastSeenAt: now });
    if (!normalized) throw new Error('id and baseUrl are required');
    registeredBackends = [normalized, ...registeredBackends.filter((backend) => backend.id !== normalized.id)];
    writeStoredBackends(registeredBackends);
    return { ...normalized, status: computeStatus(normalized) };
  }

  function heartbeat(id, patch = {}) {
    const existing = registeredBackends.find((backend) => backend.id === id);
    if (!existing) throw new Error('registered backend not found');
    const next = normalizeBackend({ ...existing, ...patch, id, lastSeenAt: new Date().toISOString() });
    registeredBackends = registeredBackends.map((backend) => (backend.id === id ? next : backend));
    writeStoredBackends(registeredBackends);
    return { ...next, status: computeStatus(next) };
  }

  function remove(id) {
    const before = registeredBackends.length;
    registeredBackends = registeredBackends.filter((backend) => backend.id !== id);
    if (registeredBackends.length !== before) writeStoredBackends(registeredBackends);
    return registeredBackends.length !== before;
  }

  return { list, find, register, heartbeat, remove };
}
