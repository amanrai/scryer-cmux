type HostBarProps = {
  hostName: string;
  defaultHostName: string;
  machineNameColor?: string;
  stateStatus: 'loading' | 'synced' | 'offline';
  interactionsEnabled: boolean;
  machineIcons: string[];
  activePaneInteractionState: { hasProducer: boolean; hasPending: boolean };
  activePaneActivityState: { count: number; unread: number; latestLevel?: string; latestKind?: string };
  buttonSettings: { fontSize: boolean; interaction: boolean; agentUpdates: boolean; scryer: boolean; quickInputs: boolean };
  onToggleInteractions: () => void;
  onAdjustActivePaneFontSize: (delta: number) => void;
  onOpenActivePaneInteraction: () => void;
  onOpenActivePaneActivity: () => void;
  onOpenActivePaneScryerPicker: () => void;
  onOpenActivePaneQuickInputs: () => void;
};

export function HostBar({
  hostName,
  defaultHostName,
  machineNameColor,
  stateStatus,
  interactionsEnabled,
  machineIcons,
  activePaneInteractionState,
  activePaneActivityState,
  buttonSettings,
  onToggleInteractions,
  onAdjustActivePaneFontSize,
  onOpenActivePaneInteraction,
  onOpenActivePaneActivity,
  onOpenActivePaneScryerPicker,
  onOpenActivePaneQuickInputs,
}: HostBarProps) {
  return (
    <header className="host-bar">
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
        className="host-identity"
        type="button"
        title="Command palette"
        aria-label="Open command palette"
        onClick={() => window.dispatchEvent(new CustomEvent('smux:open-palette'))}
      >
        {machineIcons.map((icon, index) => <i key={`${icon}-${index}`} className={`host-machine-icon ${stateStatus} ${icon}`} aria-hidden="true" />)}
        <span className="host-name" title={`${defaultHostName} · ${stateStatus}`}><b style={machineNameColor ? { color: machineNameColor } : undefined}>{hostName}</b></span>
      </button>
      <div className="host-spacer" />
      <div className="host-actions" aria-label="Active pane controls">
        {buttonSettings.fontSize ? (
          <>
            <button className="host-action" type="button" title="Decrease font size" aria-label="Decrease font size" onClick={() => onAdjustActivePaneFontSize(-1)}>
              <i className="fa-solid fa-magnifying-glass-minus" aria-hidden="true" />
            </button>
            <button className="host-action" type="button" title="Increase font size" aria-label="Increase font size" onClick={() => onAdjustActivePaneFontSize(1)}>
              <i className="fa-solid fa-magnifying-glass-plus" aria-hidden="true" />
            </button>
          </>
        ) : null}
        {buttonSettings.fontSize && (buttonSettings.interaction || buttonSettings.agentUpdates || buttonSettings.scryer || buttonSettings.quickInputs) ? <span className="host-action-divider" aria-hidden="true" /> : null}
        {buttonSettings.interaction ? (
          <button
            className={`host-action interaction ${activePaneInteractionState.hasProducer ? 'listening' : ''}${activePaneInteractionState.hasPending ? ' pending' : ''}`}
            type="button"
            title={activePaneInteractionState.hasPending ? 'Open pending interaction' : activePaneInteractionState.hasProducer ? 'Listening for interactions' : 'No interaction producer detected'}
            aria-label="Interactions"
            onClick={onOpenActivePaneInteraction}
          >
            <i className="fa-solid fa-comments" aria-hidden="true" />
          </button>
        ) : null}
        {buttonSettings.agentUpdates ? (
          <button
            className={`host-action activity ${activePaneActivityState.unread ? 'unread' : ''} ${activePaneActivityState.latestLevel ? `level-${activePaneActivityState.latestLevel}` : ''}`}
            type="button"
            title={activePaneActivityState.count ? `Open agent activity (${activePaneActivityState.count} updates)` : activePaneInteractionState.hasProducer ? 'Open agent activity' : 'No interaction producer detected'}
            aria-label="Agent activity"
            onClick={onOpenActivePaneActivity}
          >
            <i className="fa-solid fa-timeline" aria-hidden="true" />
            {activePaneActivityState.unread ? <span className="host-action-badge">{Math.min(99, activePaneActivityState.unread)}</span> : null}
          </button>
        ) : null}
        {buttonSettings.scryer ? (
          <button className="host-action" type="button" title="Pick Scryer project/ticket" aria-label="Pick Scryer project or ticket" onClick={onOpenActivePaneScryerPicker}>
            <i className="fa-solid fa-diagram-project" aria-hidden="true" />
          </button>
        ) : null}
        {buttonSettings.quickInputs ? (
          <button className="host-action" type="button" title="Quick inputs" aria-label="Quick inputs" onClick={onOpenActivePaneQuickInputs}>
            <i className="fa-solid fa-keyboard" aria-hidden="true" />
          </button>
        ) : null}
      </div>
    </header>
  );
}
