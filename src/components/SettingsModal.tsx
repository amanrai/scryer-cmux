import { useEffect, useMemo, useState } from 'react';
import { machineIconOptions, type MachineIconId } from '../machineIcons';

type SettingsPage = 'machine';

type SettingsModalProps = {
  hostName: string;
  defaultHostName: string;
  selectedMachineIcons: MachineIconId[];
  onSetMachineIcons: (icons: MachineIconId[]) => void;
  onSetMachineName: (name: string) => void;
  onClose: () => void;
};

export function SettingsModal({ hostName, defaultHostName, selectedMachineIcons, onSetMachineIcons, onSetMachineName, onClose }: SettingsModalProps) {
  const [page, setPage] = useState<SettingsPage>('machine');
  const groups = useMemo(() => ['OS', 'Machine'].map((group) => ({
    group,
    options: machineIconOptions.filter((option) => option.group === group),
  })), []);

  function toggleIcon(id: MachineIconId) {
    if (selectedMachineIcons.includes(id)) onSetMachineIcons(selectedMachineIcons.filter((icon) => icon !== id));
    else onSetMachineIcons([...selectedMachineIcons, id]);
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
          </nav>
          <div className="settings-page">
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
                <button type="button" className="ghost-button" disabled={hostName === defaultHostName} onClick={() => onSetMachineName(defaultHostName)}>Use default</button>
              </div>
            </div>
            <div className="machine-preview" aria-label="Machine preview">
              {selectedMachineIcons.map((icon) => (
                <i key={icon} className={machineIconOptions.find((option) => option.id === icon)?.icon} aria-hidden="true" />
              ))}
              <span>{hostName.trim() || defaultHostName}</span>
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
          </div>
        </div>
      </section>
    </div>
  );
}
