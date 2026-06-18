import { chmodSync, existsSync } from 'node:fs';
import path from 'node:path';

if (process.platform !== 'darwin') process.exit(0);

for (const arch of ['arm64', 'x64']) {
  const helper = path.resolve('node_modules', 'node-pty', 'prebuilds', `darwin-${arch}`, 'spawn-helper');
  if (!existsSync(helper)) continue;
  try {
    chmodSync(helper, 0o755);
  } catch (error) {
    console.warn(`Could not chmod ${helper}: ${error.message}`);
  }
}
