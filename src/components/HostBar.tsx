type HostBarProps = {
  hostName: string;
  stateStatus: 'loading' | 'synced' | 'offline';
  interactionsEnabled: boolean;
  onToggleInteractions: () => void;
};

export function HostBar({ hostName, stateStatus, interactionsEnabled, onToggleInteractions }: HostBarProps) {
  return (
    <header className="host-bar">
      <div className="host-identity">
        <span className={`host-status-dot ${stateStatus}`} aria-hidden="true" />
        <span className="host-name" title={hostName}><b>{hostName}</b></span>
      </div>
      <div className="host-spacer" />
      <button
        className={`palette-trigger interactions-toggle${interactionsEnabled ? ' enabled' : ' disabled'}`}
        type="button"
        title={`Interactions ${interactionsEnabled ? 'on' : 'off'}`}
        aria-label={`Turn interactions ${interactionsEnabled ? 'off' : 'on'}`}
        aria-pressed={interactionsEnabled}
        onClick={onToggleInteractions}
      >
        <i className={`fa-solid ${interactionsEnabled ? 'fa-comments' : 'fa-comment-slash'}`} aria-hidden="true" />
      </button>
      <button
        className="palette-trigger"
        type="button"
        title="Command palette (⌘K)"
        aria-label="Open command palette"
        onClick={() => window.dispatchEvent(new CustomEvent('smux:open-palette'))}
      >
        <span className="palette-trigger-label">Commands</span>
        <span className="kbd">⌘K</span>
      </button>
    </header>
  );
}
