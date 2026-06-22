import { useEffect, useMemo, useState } from 'react';
import { machineIconOptions, type MachineIconId } from '../machineIcons';

type SettingsPage = 'machine' | 'buttons';

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

export function SettingsModal({ hostName, defaultHostName, selectedMachineIcons, onSetMachineIcons, onSetMachineName, machineNameColor, onSetMachineNameColor, buttonSettings, onSetButtonSettings, onClose }: SettingsModalProps) {
  const [page, setPage] = useState<SettingsPage>('machine');
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
          </nav>
          {page === 'machine' ? <div className="settings-page">
            <div className="settings-page-heading">
              <h3>Machine customization</h3>
              <p>Customize <strong>{defaultHostName}</strong>. This is local to this browser.</p>
            </div>
            <div className="machine-name-row">
              <label className="field-label" htmlFor="machine-display-name">Display name</label>
              <div className="machine-name-controls">
                <input
                  id="machine-display-name"
                  className="rename-input"
                  value={hostName}
                  onChange={(event) => onSetMachineName(event.target.value)}
                />
                <label className="machine-name-color" title="Machine name color">
                  <span className="sr-only">Machine name color</span>
                  <input type="color" value={machineNameColor ?? '#e8b65a'} onChange={(event) => onSetMachineNameColor(event.target.value)} />
                </label>
              </div>
            </div>
            <div className="machine-preview" aria-label="Machine preview">
              {selectedMachineIcons.map((icon) => (
                <i key={icon} className={machineIconOptions.find((option) => option.id === icon)?.icon} aria-hidden="true" />
              ))}
              <span style={machineNameColor ? { color: machineNameColor } : undefined}>{hostName.trim() || defaultHostName}</span>
            </div>
            {groups.map(({ group, options }) => (
              <section key={group} className="machine-icon-group">
                <div className="field-label">{group}</div>
                <div className="machine-icon-grid">
                  {options.map((option) => {
                    const selected = selectedMachineIcons.includes(option.id);
                    return (
                      <button key={option.id} type="button" className={`machine-icon-choice${selected ? ' selected' : ''}`} aria-pressed={selected} onClick={() => toggleIcon(option.id)}>
                        <i className={option.icon} aria-hidden="true" />
                        <span>{option.label}</span>
                      </button>
                    );
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
        </div>
      </section>
    </div>
  );
}
