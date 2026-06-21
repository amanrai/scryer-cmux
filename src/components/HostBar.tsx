type HostBarProps = {
  hostName: string;
  stateStatus: 'loading' | 'synced' | 'offline';
};

export function HostBar({ hostName, stateStatus }: HostBarProps) {
  return (
    <header className="host-bar">
      <div className="host-identity">
        <span className={`host-status-dot ${stateStatus}`} aria-hidden="true" />
        <span className="host-name" title={hostName}><b>{hostName}</b></span>
      </div>
      <div className="host-spacer" />
      <button
        className="palette-trigger"
        type="button"
        title="Command palette (⌘K)"
        aria-label="Open command palette"
        onClick={() => window.dispatchEvent(new CustomEvent('smux:open-palette'))}
      >
        <i className="fa-solid fa-magnifying-glass" aria-hidden="true" />
        <span className="palette-trigger-label">Commands</span>
        <span className="kbd">⌘K</span>
      </button>
    </header>
  );
}
