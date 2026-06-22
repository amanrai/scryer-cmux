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
  paneFontSize: Record<string, number>;
  themeName: SmuxThemeName;
  terminalFocusToken: number;
  interactionsEnabled: boolean;
  onActivateWorkspace: (workspaceId: string) => void;
  onSetActivePane: (paneId: string, workspaceId?: string) => void;
  onOpenCommandInput: (pane: PaneModel, workspaceId: string) => void;
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
  paneFontSize,
  themeName,
  terminalFocusToken,
  interactionsEnabled,
  onActivateWorkspace,
  onSetActivePane,
  onOpenCommandInput,
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
              {workspace.panes.slice(0, 1).map((pane) => {
                const isActive = workspace.id === activeWorkspaceId;
                return (
                  <article
                    key={pane.id}
                    className={`pane terminal-pane-card${isActive ? ' active' : ''}`}
                    onMouseDown={() => {
                      onActivateWorkspace(workspace.id);
                      onSetActivePane(pane.id, workspace.id);
                    }}
                  >
                    <TerminalPane
                      paneId={pane.id}
                      active={isActive}
                      accentColor={workspace.color}
                      themeName={themeName}
                      fontSize={paneFontSize[pane.id] ?? DEFAULT_FONT_SIZE}
                      focusToken={isActive ? terminalFocusToken : 0}
                      interactionsEnabled={interactionsEnabled}
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
