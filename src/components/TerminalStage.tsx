import { TerminalPane } from '../TerminalPane';
import type { TerminalPaneApi } from '../TerminalPane';
import { DEFAULT_FONT_SIZE } from '../constants';
import type { SmuxThemeName } from '../terminal/theme';
import type { PaneModel, PaneStatus, WorkspaceModel } from '../types';

type TerminalStageProps = {
  stateReady: boolean;
  hostName: string;
  workspaces: WorkspaceModel[];
  activeWorkspaceId: string;
  paneStatus: Record<string, PaneStatus>;
  paneFontSize: Record<string, number>;
  paneInteractionState: Record<string, { hasProducer: boolean; hasPending: boolean }>;
  paneActivityState: Record<string, { count: number; unread: number; latestLevel?: string; latestKind?: string }>;
  themeName: SmuxThemeName;
  terminalFocusToken: number;
  onActivateWorkspace: (workspaceId: string) => void;
  onSetActivePane: (paneId: string, workspaceId?: string) => void;
  onRenamePane: (pane: PaneModel, workspaceId: string) => void;
  onAdjustPaneFontSize: (paneId: string, delta: number) => void;
  onOpenCommandInput: (pane: PaneModel, workspaceId: string) => void;
  onOpenPaneInteraction: (paneId: string) => void;
  onOpenPaneActivity: (paneId: string) => void;
  onOpenPaneScryerPicker: (paneId: string) => void;
  onOpenPaneQuickInputs: (paneId: string) => void;
  onSplitPane: (direction: WorkspaceModel['layout']) => void;
  onClosePane: (paneId: string) => void;
  onPaneStatus: (paneId: string, status: PaneStatus) => void;
  onPaneInteractionState: (paneId: string, state: { hasProducer: boolean; hasPending: boolean }) => void;
  onPaneActivityState: (paneId: string, state: { count: number; unread: number; latestLevel?: string; latestKind?: string }) => void;
  onRegisterPaneApi: (paneId: string, api: TerminalPaneApi | null) => void;
};

export function TerminalStage({
  stateReady,
  hostName,
  workspaces,
  activeWorkspaceId,
  paneStatus,
  paneFontSize,
  paneInteractionState,
  paneActivityState,
  themeName,
  terminalFocusToken,
  onActivateWorkspace,
  onSetActivePane,
  onRenamePane,
  onAdjustPaneFontSize,
  onOpenCommandInput,
  onOpenPaneInteraction,
  onOpenPaneActivity,
  onOpenPaneScryerPicker,
  onOpenPaneQuickInputs,
  onSplitPane,
  onClosePane,
  onPaneStatus,
  onPaneInteractionState,
  onPaneActivityState,
  onRegisterPaneApi,
}: TerminalStageProps) {
  return (
    <main className="workspace-main">
      <section className="terminal-stage">
        {!stateReady ? (
          <div className="terminal-loading">
            <span className="spinner" aria-hidden="true" />
            <span>Connecting to {hostName}…</span>
          </div>
        ) : workspaces.map((workspace) => (
          <div
            key={workspace.id}
            className={`workspace-surface${workspace.id === activeWorkspaceId ? ' active' : ''}`}
            aria-hidden={workspace.id !== activeWorkspaceId}
          >
            <div className={`pane-grid ${workspace.layout}`}>
              {workspace.panes.map((pane) => {
                const isActive = workspace.id === activeWorkspaceId && pane.id === workspace.activePaneId;
                const status = paneStatus[pane.id] ?? 'connecting';
                const interactionState = paneInteractionState[pane.id] ?? { hasProducer: false, hasPending: false };
                const activityState = paneActivityState[pane.id] ?? { count: 0, unread: 0 };
                return (
                  <article
                    key={pane.id}
                    className={`pane terminal-pane-card${isActive ? ' active' : ''}`}
                    onMouseDown={() => {
                      onActivateWorkspace(workspace.id);
                      onSetActivePane(pane.id, workspace.id);
                    }}
                  >
                    <div className="pane-titlebar">
                      <button
                        className="pane-name"
                        type="button"
                        title="Rename terminal"
                        onClick={(event) => {
                          event.stopPropagation();
                          onActivateWorkspace(workspace.id);
                          onSetActivePane(pane.id, workspace.id);
                          onRenamePane(pane, workspace.id);
                        }}
                      >
                        <span className={`pane-dot ${status}`} title={status} aria-hidden="true" />
                        <span className="pane-title-text">{pane.title}</span>
                        <i className="pane-name-edit fa-solid fa-pen" aria-hidden="true" />
                      </button>
                      <div className="pane-actions">
                        <button className="pane-action" type="button" title="Decrease font size" aria-label="Decrease font size" onClick={() => onAdjustPaneFontSize(pane.id, -1)}>
                          <i className="fa-solid fa-magnifying-glass-minus" aria-hidden="true" />
                        </button>
                        <button className="pane-action" type="button" title="Increase font size" aria-label="Increase font size" onClick={() => onAdjustPaneFontSize(pane.id, 1)}>
                          <i className="fa-solid fa-magnifying-glass-plus" aria-hidden="true" />
                        </button>
                        <span className="pane-action-divider" aria-hidden="true" />
                        <button
                          className={`pane-action interaction ${interactionState.hasProducer ? 'listening' : ''}${interactionState.hasPending ? ' pending' : ''}`}
                          type="button"
                          title={interactionState.hasPending ? 'Open pending interaction' : interactionState.hasProducer ? 'Listening for interactions' : 'No interaction producer detected'}
                          aria-label="Interactions"
                          onClick={() => onOpenPaneInteraction(pane.id)}
                        >
                          <i className="fa-solid fa-comments" aria-hidden="true" />
                        </button>
                        <button
                          className={`pane-action activity ${activityState.unread ? 'unread' : ''} ${activityState.latestLevel ? `level-${activityState.latestLevel}` : ''}`}
                          type="button"
                          title={activityState.count ? `Open agent activity (${activityState.count} updates)` : interactionState.hasProducer ? 'Open agent activity' : 'No interaction producer detected'}
                          aria-label="Agent activity"
                          onClick={() => onOpenPaneActivity(pane.id)}
                        >
                          <i className="fa-solid fa-timeline" aria-hidden="true" />
                          {activityState.unread ? <span className="pane-action-badge">{Math.min(99, activityState.unread)}</span> : null}
                        </button>
                        <button className="pane-action" type="button" title="Pick Scryer project/ticket" aria-label="Pick Scryer project or ticket" onClick={() => onOpenPaneScryerPicker(pane.id)}>
                          <i className="fa-solid fa-diagram-project" aria-hidden="true" />
                        </button>
                        <button className="pane-action" type="button" title="Quick inputs" aria-label="Quick inputs" onClick={() => onOpenPaneQuickInputs(pane.id)}>
                          <i className="fa-solid fa-keyboard" aria-hidden="true" />
                        </button>
                        <span className="pane-action-divider" aria-hidden="true" />
                        <button className="pane-action" type="button" title="New terminal right (⌘T)" aria-label="New terminal right" onClick={() => onSplitPane('row')}>
                          <i className="fa-solid fa-grip-lines-vertical" aria-hidden="true" />
                        </button>
                        <button className="pane-action" type="button" title="New terminal down" aria-label="New terminal down" onClick={() => onSplitPane('column')}>
                          <i className="fa-solid fa-grip-lines" aria-hidden="true" />
                        </button>
                        {workspace.panes.length > 1 ? (
                          <button className="pane-action danger" type="button" title="Close pane" aria-label="Close pane" onClick={() => onClosePane(pane.id)}>
                            <i className="fa-solid fa-xmark" aria-hidden="true" />
                          </button>
                        ) : null}
                      </div>
                    </div>
                    <TerminalPane
                      paneId={pane.id}
                      active={isActive}
                      accentColor={workspace.color}
                      themeName={themeName}
                      fontSize={paneFontSize[pane.id] ?? DEFAULT_FONT_SIZE}
                      focusToken={isActive ? terminalFocusToken : 0}
                      onStatus={onPaneStatus}
                      onRegisterApi={onRegisterPaneApi}
                      onInteractionState={onPaneInteractionState}
                      onActivityState={onPaneActivityState}
                      onOpenCommandInput={() => {
                        onActivateWorkspace(workspace.id);
                        onSetActivePane(pane.id, workspace.id);
                        onOpenCommandInput(pane, workspace.id);
                      }}
                    />
                  </article>
                );
              })}
            </div>
          </div>
        ))}
      </section>
    </main>
  );
}
