import type { SmuxThemeName } from '../terminal/theme';

type HostBarProps = {
  hostName: string;
  stateStatus: 'loading' | 'synced' | 'offline';
  themeName: SmuxThemeName;
  onToggleTheme: () => void;
};

export function HostBar({ hostName, stateStatus, themeName, onToggleTheme }: HostBarProps) {
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
        title={themeName === 'sunlight' ? 'Switch to dark theme' : 'Switch to hi-viz sunlight theme'}
        aria-label="Toggle hi-viz sunlight theme"
        onClick={onToggleTheme}
      >
        <i className="fa-solid fa-sun" aria-hidden="true" />
        <span>{themeName === 'sunlight' ? 'Sunlight' : 'Dark'}</span>
      </button>
      <button
        className="palette-trigger"
        type="button"
        title="Command palette"
        aria-label="Open command palette"
        onClick={() => window.dispatchEvent(new CustomEvent('smux:open-palette'))}
      >
        <span className="kbd">⌘K</span>
      </button>
    </header>
  );
}
