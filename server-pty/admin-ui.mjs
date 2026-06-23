import { createServer } from 'node:http';
import { adminPort, port } from './config.mjs';

function html() {
  const defaultApiPort = port;
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>amux PTY admin</title>
  <style>
    :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #111318; color: #f4f0e8; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px; background: radial-gradient(circle at top left, rgba(90,166,240,.18), transparent 34rem), #111318; }
    main { width: min(760px, 100%); display: grid; gap: 18px; padding: 24px; background: #191c23; border: 1px solid rgba(255,255,255,.12); border-radius: 18px; box-shadow: 0 24px 70px rgba(0,0,0,.45); }
    h1 { margin: 0; font-size: 22px; letter-spacing: -0.02em; }
    p { margin: 6px 0 0; color: #aeb4c0; line-height: 1.5; }
    form { display: grid; gap: 14px; }
    label { display: grid; gap: 7px; color: #aeb4c0; font-size: 12px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }
    input { height: 42px; padding: 0 13px; color: #f4f0e8; background: #0d0f13; border: 1px solid rgba(255,255,255,.16); border-radius: 10px; font-size: 14px; }
    input[type="checkbox"] { width: 17px; height: 17px; }
    .check { display: flex; align-items: center; gap: 10px; color: #d7d2c8; text-transform: none; letter-spacing: 0; font-weight: 500; }
    .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
    .actions { display: flex; flex-wrap: wrap; gap: 10px; justify-content: flex-end; }
    button { height: 40px; padding: 0 16px; border: 1px solid rgba(255,255,255,.16); border-radius: 10px; background: #242936; color: #f4f0e8; font-weight: 700; cursor: pointer; }
    button.primary { background: #e8b65a; color: #111318; border-color: transparent; }
    button:disabled { opacity: .5; cursor: not-allowed; }
    .status { display: grid; gap: 7px; padding: 13px; background: #0d0f13; border: 1px solid rgba(255,255,255,.1); border-radius: 12px; color: #aeb4c0; font-size: 13px; }
    .error { color: #ff9b91; }
    .ok { color: #86df98; }
    code { color: #e8b65a; }
    @media (max-width: 640px) { .grid { grid-template-columns: 1fr; } main { padding: 18px; } }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>amux PTY admin</h1>
      <p>Configure this machine-local PTY server and register it with a gateway. PTY API: <code id="api-label"></code></p>
    </header>
    <form id="form">
      <label>Gateway URL<input id="gatewayUrl" placeholder="http://gateway-host:43223" /></label>
      <div class="grid">
        <label>Machine ID<input id="machineId" /></label>
        <label>Machine name<input id="machineName" /></label>
      </div>
      <label>PTY URL reachable by gateway<input id="publicUrl" placeholder="http://this-machine:43222" /></label>
      <label class="check"><input id="heartbeatEnabled" type="checkbox" /> Heartbeat enabled</label>
      <div class="actions">
        <button type="button" id="reload">Reload</button>
        <button type="button" id="save">Save</button>
        <button type="submit" class="primary" id="register">Register with gateway</button>
      </div>
    </form>
    <section class="status" id="status">Loading…</section>
  </main>
  <script>
    const API_BASE = 'http://' + location.hostname + ':${defaultApiPort}';
    const ids = ['gatewayUrl', 'machineId', 'machineName', 'publicUrl', 'heartbeatEnabled'];
    const el = Object.fromEntries(ids.map((id) => [id, document.getElementById(id)]));
    const statusEl = document.getElementById('status');
    const apiLabel = document.getElementById('api-label');
    apiLabel.textContent = API_BASE;
    let busy = false;

    function setBusy(next) {
      busy = next;
      for (const button of document.querySelectorAll('button')) button.disabled = busy;
    }

    function show(payload, message = '') {
      const status = payload?.status || {};
      statusEl.innerHTML = [
        message ? '<div>' + escapeHtml(message) + '</div>' : '',
        '<div>Registration: <strong class="' + (status.registered ? 'ok' : '') + '">' + (status.registered ? 'registered' : 'not registered') + '</strong></div>',
        '<div>Last success: ' + escapeHtml(status.lastSuccessAt ? new Date(status.lastSuccessAt).toLocaleString() : 'never') + '</div>',
        status.lastError ? '<div class="error">' + escapeHtml(status.lastError) + '</div>' : ''
      ].join('');
    }

    function escapeHtml(value) {
      return String(value || '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
    }

    function draft() {
      return {
        gatewayUrl: el.gatewayUrl.value.trim(),
        machineId: el.machineId.value.trim(),
        machineName: el.machineName.value.trim(),
        publicUrl: el.publicUrl.value.trim(),
        heartbeatEnabled: el.heartbeatEnabled.checked,
      };
    }

    function fill(payload) {
      const config = payload.config || {};
      el.gatewayUrl.value = config.gatewayUrl || '';
      el.machineId.value = config.machineId || '';
      el.machineName.value = config.machineName || '';
      el.publicUrl.value = config.publicUrl || '';
      el.heartbeatEnabled.checked = Boolean(config.heartbeatEnabled);
      show(payload);
    }

    async function request(path, options) {
      const response = await fetch(API_BASE + path, options);
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || 'Request failed: ' + response.status);
      return payload;
    }

    async function load() {
      setBusy(true);
      try { fill(await request('/api/pty-config')); }
      catch (error) { statusEl.innerHTML = '<div class="error">' + escapeHtml(error.message) + '</div>'; }
      finally { setBusy(false); }
    }

    async function save(register) {
      setBusy(true);
      try {
        const payload = await request('/api/pty-config' + (register ? '/register' : ''), {
          method: register ? 'POST' : 'PUT',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(draft()),
        });
        fill(payload);
        show(payload, register ? 'Registered with gateway.' : 'Saved PTY config.');
      } catch (error) {
        statusEl.innerHTML = '<div class="error">' + escapeHtml(error.message) + '</div>';
      } finally { setBusy(false); }
    }

    document.getElementById('reload').addEventListener('click', load);
    document.getElementById('save').addEventListener('click', () => save(false));
    document.getElementById('form').addEventListener('submit', (event) => { event.preventDefault(); save(true); });
    load();
  </script>
</body>
</html>`;
}

const server = createServer((req, res) => {
  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(html());
    return;
  }
  if (req.url === '/healthz') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, service: 'amux-pty-admin', port: adminPort, ptyApiPort: port }));
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
});

server.listen(adminPort, '0.0.0.0', () => {
  console.log(`amux pty admin UI listening on http://0.0.0.0:${adminPort}`);
});
