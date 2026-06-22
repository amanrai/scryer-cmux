import { execFileSync } from 'node:child_process';
import os from 'node:os';

export function getDisplayHostName() {
  for (const binary of ['tailscale', '/Applications/Tailscale.app/Contents/MacOS/Tailscale']) {
    try {
      const status = JSON.parse(execFileSync(binary, ['status', '--json'], { encoding: 'utf8', timeout: 1000 }));
      const dnsName = String(status?.Self?.DNSName ?? '').replace(/\.$/, '');
      if (dnsName) return dnsName;
      const hostName = String(status?.Self?.HostName ?? '');
      if (hostName) return hostName;
    } catch {}
  }
  return os.hostname();
}
