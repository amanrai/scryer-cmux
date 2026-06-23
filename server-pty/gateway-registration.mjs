import fs from 'node:fs';
import os from 'node:os';
import { gatewayConfigPath, port } from './config.mjs';
import { getDisplayHostName } from './host-name.mjs';

const defaultHeartbeatMs = Number(process.env.AMUX_PTY_HEARTBEAT_MS ?? 15_000);

function machineIdFromHost() {
  return getDisplayHostName().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'amux-pty';
}

function defaultConfig() {
  const label = getDisplayHostName();
  return {
    gatewayUrl: process.env.AMUX_GATEWAY_URL ?? '',
    machineId: process.env.AMUX_PTY_MACHINE_ID ?? machineIdFromHost(),
    machineName: process.env.AMUX_PTY_MACHINE_NAME ?? label,
    publicUrl: process.env.AMUX_PTY_PUBLIC_URL ?? `http://127.0.0.1:${port}`,
    heartbeatEnabled: process.env.AMUX_PTY_HEARTBEAT_ENABLED !== '0',
    heartbeatMs: defaultHeartbeatMs,
  };
}

let config = loadConfig();
let status = { registered: false };
let heartbeatTimer;

export function loadConfig() {
  try {
    if (!fs.existsSync(gatewayConfigPath)) return defaultConfig();
    return { ...defaultConfig(), ...JSON.parse(fs.readFileSync(gatewayConfigPath, 'utf8')) };
  } catch (error) {
    console.warn(`Could not read PTY gateway config: ${error instanceof Error ? error.message : String(error)}`);
    return defaultConfig();
  }
}

export function getConfigPayload() {
  return { config, status };
}

export function saveConfig(next) {
  config = {
    ...config,
    gatewayUrl: String(next.gatewayUrl ?? '').replace(/\/$/, ''),
    machineId: String(next.machineId ?? config.machineId).trim() || machineIdFromHost(),
    machineName: String(next.machineName ?? config.machineName).trim() || getDisplayHostName(),
    publicUrl: String(next.publicUrl ?? config.publicUrl).replace(/\/$/, ''),
    heartbeatEnabled: Boolean(next.heartbeatEnabled),
    heartbeatMs: Math.max(5_000, Number(next.heartbeatMs ?? config.heartbeatMs ?? defaultHeartbeatMs)),
  };
  fs.writeFileSync(gatewayConfigPath, `${JSON.stringify(config, null, 2)}\n`);
  restartHeartbeat();
  return getConfigPayload();
}

function registrationPayload() {
  return {
    id: config.machineId,
    label: config.machineName,
    kind: 'pty',
    baseUrl: config.publicUrl,
    transport: 'tailnet',
    capabilities: ['terminal', 'state', 'upload', 'pm-proxy'],
    hostInfo: {
      hostname: os.hostname(),
      displayName: getDisplayHostName(),
      platform: process.platform,
      osType: os.type(),
      arch: process.arch,
      port,
    },
  };
}

async function postJson(url, payload) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  let parsed;
  try { parsed = text ? JSON.parse(text) : {}; } catch { parsed = { body: text }; }
  if (!response.ok) throw new Error(parsed.error ?? `gateway returned ${response.status}`);
  return parsed;
}

export async function registerWithGateway() {
  if (!config.gatewayUrl) throw new Error('gatewayUrl is required');
  if (!config.publicUrl) throw new Error('publicUrl is required');
  try {
    const result = await postJson(`${config.gatewayUrl}/api/backends/register`, registrationPayload());
    status = { registered: true, lastSuccessAt: new Date().toISOString(), lastError: undefined, gatewayResponse: result.backend };
    restartHeartbeat();
    return getConfigPayload();
  } catch (error) {
    status = { ...status, registered: false, lastAttemptAt: new Date().toISOString(), lastError: error instanceof Error ? error.message : String(error) };
    throw error;
  }
}

async function sendHeartbeat() {
  if (!config.gatewayUrl || !config.machineId || !config.heartbeatEnabled) return;
  try {
    const result = await postJson(`${config.gatewayUrl}/api/backends/${encodeURIComponent(config.machineId)}/heartbeat`, registrationPayload());
    status = { registered: true, lastSuccessAt: new Date().toISOString(), lastError: undefined, gatewayResponse: result.backend };
  } catch (error) {
    status = { ...status, registered: false, lastAttemptAt: new Date().toISOString(), lastError: error instanceof Error ? error.message : String(error) };
  }
}

export function restartHeartbeat() {
  if (heartbeatTimer) clearInterval(heartbeatTimer);
  heartbeatTimer = undefined;
  if (!config.gatewayUrl || !config.heartbeatEnabled) return;
  heartbeatTimer = setInterval(sendHeartbeat, config.heartbeatMs);
  heartbeatTimer.unref?.();
}

export function startGatewayRegistration() {
  restartHeartbeat();
  if (config.gatewayUrl && config.heartbeatEnabled) {
    registerWithGateway().catch((error) => {
      status = { ...status, registered: false, lastError: error instanceof Error ? error.message : String(error) };
    });
  }
}
