import { useEffect, useMemo, useState } from 'react';
import { API_BASE } from '../constants';
import { machineIconOptions, type MachineIconId } from '../machineIcons';
import type { BackendMachine, PtyConfigPayload } from '../types';

type SettingsPage = 'machine' | 'buttons' | 'pty' | 'gateway';

type ButtonSettings = { fontSize: boolean; interaction: boolean; agentUpdates: boolean; scryer: boolean; quickInputs: boolean };

type SettingsModalProps = {
  hostName: string;
  defaultHostName: string;
  selectedMachineIcons: MachineIconId[];
  onSetMachineIcons: (icons: MachineIconId[]) => void;
  onSetMachineName: (name: string) => void;
  machineNameColor?: string;
  onSetMachineNameColor: (color: string) => void;
  buttonSettings: ButtonSettings;
  onSetButtonSettings: (settings: ButtonSettings) => void;
  onClose: () => void;
};

function statusLabel(status?: string) {
  return status || 'unknown';
}

function formatLastSeen(value?: string) {
  if (!value) return 'never';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

export function SettingsModal({ hostName, defaultHostName, selectedMachineIcons, onSetMachineIcons, onSetMachineName, machineNameColor, onSetMachineNameColor, buttonSettings, onSetButtonSettings, onClose }: SettingsModalProps) {
  const [page, setPage] = useState<SettingsPage>('machine');
  const [ptyPayload, setPtyPayload] = useState<PtyConfigPayload | null>(null);
  const [ptyDraft, setPtyDraft] = useState<PtyConfigPayload['config'] | null>(null);
  const [ptyMessage, setPtyMessage] = useState('');
  const [ptyBusy, setPtyBusy] = useState(false);
  const [backends, setBackends] = useState<BackendMachine[]>([]);
  const [selectedBackendId, setSelectedBackendId] = useState('');
  const [gatewayMessage, setGatewayMessage] = useState('');
  const [gatewayBusy, setGatewayBusy] = useState(false);
  const groups = useMemo(() => ['OS', 'Machine'].map((group) => ({
    group,
    options: machineIconOptions.filter((option) => option.group === group),
  })), []);

  function toggleIcon(id: MachineIconId) {
    if (selectedMachineIcons.includes(id)) onSetMachineIcons(selectedMachineIcons.filter((icon) => icon !== id));
    else onSetMachineIcons([...selectedMachineIcons, id]);
  }

  function toggleButton(key: keyof ButtonSettings) {
    onSetButtonSettings({ ...buttonSettings, [key]: !buttonSettings[key] });
  }

  async function loadPtyConfig() {
    setPtyBusy(true);
    setPtyMessage('');
    try {
      const response = await fetch(`${API_BASE}/api/pty-config`);
      if (!response.ok) throw new Error(`PTY config unavailable (${response.status})`);
      const payload = await response.json() as PtyConfigPayload;
      setPtyPayload(payload);
      setPtyDraft(payload.config);
    } catch (error) {
      setPtyMessage(error instanceof Error ? error.message : 'Could not load PTY config');
    } finally {
      setPtyBusy(false);
    }
  }

  async function savePtyConfig(register = false) {
    if (!ptyDraft) return;
    setPtyBusy(true);
    setPtyMessage('');
    try {
      const response = await fetch(`${API_BASE}/api/pty-config${register ? '/register' : ''}`, {
        method: register ? 'POST' : 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(ptyDraft),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || `Request failed (${response.status})`);
      setPtyPayload(payload);
      setPtyDraft(payload.config);
      setPtyMessage(register ? 'Registered with gateway.' : 'PTY config saved.');
    } catch (error) {
      setPtyMessage(error instanceof Error ? error.message : 'PTY config request failed');
    } finally {
      setPtyBusy(false);
    }
  }

  async function loadBackends() {
    setGatewayBusy(true);
    setGatewayMessage('');
    try {
      const response = await fetch(`${API_BASE}/api/backends`);
      if (!response.ok) throw new Error(`Gateway registry unavailable (${response.status})`);
      const payload = await response.json() as { backends?: BackendMachine[] };
      const reachable = (payload.backends ?? []).filter((backend) => backend.kind === 'pty' && backend.status === 'online');
      setBackends(reachable);
      setSelectedBackendId((current) => current || reachable[0]?.id || '');
    } catch (error) {
      setGatewayMessage(error instanceof Error ? error.message : 'Could not load gateway registry');
    } finally {
      setGatewayBusy(false);
    }
  }

  useEffect(() => {
    if (page === 'pty' && !ptyPayload && !ptyBusy) void loadPtyConfig();
    if (page === 'machine' || page === 'gateway') void loadBackends();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
      }
    }
    window.addEventListener('keydown', onKeyDown, { capture: true });
    return () => window.removeEventListener('keydown', onKeyDown, { capture: true });
  }, [onClose]);

  return (
    <div className="modal-layer" role="presentation" onMouseDown={onClose}>
      <section
        className="settings-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="settings-title"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="modal-titlebar">
          <div>
            <h2 id="settings-title">Settings</h2>
          </div>
          <button type="button" className="modal-close" aria-label="Close settings" onClick={onClose}>
            <i className="fa-solid fa-xmark" aria-hidden="true" />
          </button>
        </div>
        <div className="settings-shell">
          <nav className="settings-pages" aria-label="Settings pages">
            <button type="button" className={page === 'machine' ? 'active' : ''} onClick={() => setPage('machine')}>
              <i className="fa-solid fa-computer" aria-hidden="true" />
              <span>Machine</span>
            </button>
            <button type="button" className={page === 'buttons' ? 'active' : ''} onClick={() => setPage('buttons')}>
              <i className="fa-solid fa-toggle-on" aria-hidden="true" />
              <span>Buttons</span>
            </button>
            <button type="button" className={page === 'pty' ? 'active' : ''} onClick={() => setPage('pty')}>
              <i className="fa-solid fa-network-wired" aria-hidden="true" />
              <span>PTY</span>
            </button>
            <button type="button" className={page === 'gateway' ? 'active' : ''} onClick={() => setPage('gateway')}>
              <i className="fa-solid fa-diagram-project" aria-hidden="true" />
              <span>Gateway</span>
            </button>
          </nav>

          {page === 'machine' ? <div className="settings-page">
            <div className="settings-page-heading">
              <h3>Machine customization</h3>
              <p>Customize <strong>{defaultHostName}</strong>. This is local to this browser.</p>
            </div>
            <div className="machine-name-row">
              <label className="field-label" htmlFor="reachable-backend">Reachable backend</label>
              <select
                id="reachable-backend"
                className="settings-select"
                value={selectedBackendId}
                onChange={(event) => setSelectedBackendId(event.target.value)}
              >
                {backends.map((backend) => <option key={backend.id} value={backend.id}>{backend.label} · {backend.id}</option>)}
                {!backends.length ? <option value="">No reachable PTY backends</option> : null}
              </select>
            </div>
            <div className="machine-name-row">
              <label className="field-label" htmlFor="machine-display-name">Display name</label>
              <div className="machine-name-controls">
                <input id="machine-display-name" className="rename-input" value={hostName} onChange={(event) => onSetMachineName(event.target.value)} />
                <label className="machine-name-color" title="Machine name color">
                  <span className="sr-only">Machine name color</span>
                  <input type="color" value={machineNameColor ?? '#e8b65a'} onChange={(event) => onSetMachineNameColor(event.target.value)} />
                </label>
              </div>
            </div>
            <div className="machine-preview" aria-label="Machine preview">
              {selectedMachineIcons.map((icon) => <i key={icon} className={machineIconOptions.find((option) => option.id === icon)?.icon} aria-hidden="true" />)}
              <span style={machineNameColor ? { color: machineNameColor } : undefined}>{hostName.trim() || defaultHostName}</span>
            </div>
            {groups.map(({ group, options }) => (
              <section key={group} className="machine-icon-group">
                <div className="field-label">{group}</div>
                <div className="machine-icon-grid">
                  {options.map((option) => {
                    const selected = selectedMachineIcons.includes(option.id);
                    return <button key={option.id} type="button" className={`machine-icon-choice${selected ? ' selected' : ''}`} aria-pressed={selected} onClick={() => toggleIcon(option.id)}><i className={option.icon} aria-hidden="true" /><span>{option.label}</span></button>;
                  })}
                </div>
              </section>
            ))}
            <button type="button" className="ghost-button settings-clear" disabled={!selectedMachineIcons.length} onClick={() => onSetMachineIcons([])}>Clear icons</button>
          </div> : null}

          {page === 'buttons' ? <div className="settings-page">
            <div className="settings-page-heading">
              <h3>Buttons</h3>
              <p>Choose which active-pane buttons appear in the hostbar.</p>
            </div>
            <div className="settings-checkbox-list">
              {[
                ['fontSize', 'Font Size'],
                ['interaction', 'Interaction'],
                ['agentUpdates', 'Agent Updates'],
                ['scryer', 'Scryer'],
                ['quickInputs', 'Quick Inputs'],
              ].map(([key, label]) => (
                <label key={key} className="settings-checkbox-row">
                  <input type="checkbox" checked={buttonSettings[key as keyof ButtonSettings]} onChange={() => toggleButton(key as keyof ButtonSettings)} />
                  <span>{label}</span>
                </label>
              ))}
            </div>
          </div> : null}

          {page === 'pty' ? <div className="settings-page">
            <div className="settings-page-heading">
              <h3>PTY gateway registration</h3>
              <p>Configure this machine-local PTY server and register it with a gateway.</p>
            </div>
            {ptyDraft ? <div className="settings-form">
              <label><span className="field-label">Gateway URL</span><input className="rename-input" value={ptyDraft.gatewayUrl} placeholder="http://gateway-host:43223" onChange={(event) => setPtyDraft({ ...ptyDraft, gatewayUrl: event.target.value })} /></label>
              <label><span className="field-label">Machine ID</span><input className="rename-input" value={ptyDraft.machineId} onChange={(event) => setPtyDraft({ ...ptyDraft, machineId: event.target.value })} /></label>
              <label><span className="field-label">Machine name</span><input className="rename-input" value={ptyDraft.machineName} onChange={(event) => setPtyDraft({ ...ptyDraft, machineName: event.target.value })} /></label>
              <label><span className="field-label">PTY URL reachable by gateway</span><input className="rename-input" value={ptyDraft.publicUrl} placeholder="http://tailnet-host:43222" readOnly /></label>
              <label className="settings-checkbox-row"><input type="checkbox" checked={ptyDraft.heartbeatEnabled} onChange={(event) => setPtyDraft({ ...ptyDraft, heartbeatEnabled: event.target.checked })} /><span>Heartbeat enabled</span></label>
              <div className="settings-status-line">Status: {ptyPayload?.status?.registered ? 'registered' : 'not registered'} · Last success: {formatLastSeen(ptyPayload?.status?.lastSuccessAt)}</div>
              {ptyPayload?.status?.lastError ? <div className="settings-error">{ptyPayload.status.lastError}</div> : null}
              {ptyMessage ? <div className="settings-status-line">{ptyMessage}</div> : null}
              <div className="modal-actions">
                <button type="button" className="ghost-button" disabled={ptyBusy} onClick={() => void loadPtyConfig()}>Reload</button>
                <button type="button" className="ghost-button" disabled={ptyBusy} onClick={() => void savePtyConfig(false)}>Save</button>
                <button type="button" className="create-button" disabled={ptyBusy || !ptyDraft.gatewayUrl || !ptyDraft.publicUrl} onClick={() => void savePtyConfig(true)}>Register</button>
              </div>
            </div> : <div className="settings-status-line">{ptyBusy ? 'Loading PTY config…' : ptyMessage || 'PTY config unavailable.'}</div>}
          </div> : null}

          {page === 'gateway' ? <div className="settings-page">
            <div className="settings-page-heading">
              <h3>Gateway registry</h3>
              <p>Reachable PTY machines registered with the gateway this frontend is using.</p>
            </div>
            <div className="modal-actions settings-actions-left"><button type="button" className="ghost-button" disabled={gatewayBusy} onClick={() => void loadBackends()}>Refresh</button></div>
            {gatewayMessage ? <div className="settings-error">{gatewayMessage}</div> : null}
            <div className="backend-list">
              {backends.map((backend) => <article key={backend.id} className="backend-card">
                <div className="backend-card-title"><strong>{backend.label}</strong><span className={`status-pill ${statusLabel(backend.status)}`}>{statusLabel(backend.status)}</span></div>
                <div className="backend-card-meta">{backend.id} · {backend.kind} · {backend.transport ?? 'transport unknown'} · {backend.source ?? 'registry'}</div>
                {backend.baseUrl ? <div className="backend-card-url">{backend.baseUrl}</div> : null}
                <div className="backend-card-meta">Last seen: {formatLastSeen(backend.lastSeenAt)}</div>
                {backend.capabilities?.length ? <div className="backend-tags">{backend.capabilities.map((capability) => <span key={capability}>{capability}</span>)}</div> : null}
              </article>)}
              {!backends.length && !gatewayBusy ? <div className="settings-status-line">No reachable PTY backends registered.</div> : null}
              {gatewayBusy ? <div className="settings-status-line">Loading registry…</div> : null}
            </div>
          </div> : null}
        </div>
      </section>
    </div>
  );
}
