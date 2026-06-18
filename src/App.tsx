import { useMemo, useState } from 'react';
import { notifications, PaneModel, WorkspaceModel, workspaces } from './data';

type ViewMode = 'workspace' | 'inbox' | 'commands';

const statusLabel: Record<PaneModel['status'], string> = {
  idle: 'Idle',
  running: 'Running',
  'needs-input': 'Needs input',
  failed: 'Failed',
};

function cls(...values: Array<string | false | undefined>) {
  return values.filter(Boolean).join(' ');
}

export function App() {
  const [activeWorkspaceId, setActiveWorkspaceId] = useState(workspaces[0].id);
  const activeWorkspace = workspaces.find((workspace) => workspace.id === activeWorkspaceId) ?? workspaces[0];
  const [activePaneId, setActivePaneId] = useState(activeWorkspace.panes[0]?.id ?? '');
  const [view, setView] = useState<ViewMode>('workspace');
  const activePane = activeWorkspace.panes.find((pane) => pane.id === activePaneId) ?? activeWorkspace.panes[0];

  const unreadTotal = useMemo(() => workspaces.reduce((sum, workspace) => sum + workspace.unread, 0), []);

  function selectWorkspace(workspace: WorkspaceModel) {
    setActiveWorkspaceId(workspace.id);
    setActivePaneId(workspace.panes[0]?.id ?? '');
    setView('workspace');
  }

  function jumpTo(workspaceId: string, paneId: string) {
    setActiveWorkspaceId(workspaceId);
    setActivePaneId(paneId);
    setView('workspace');
  }

  return (
    <div className="app-shell">
      <aside className="sidebar" aria-label="Workspaces">
        <div className="brand">
          <div className="brand-mark">sc</div>
          <div>
            <h1>scryer-cmux</h1>
            <p>Browser agent observatory</p>
          </div>
        </div>
        <div className="sidebar-section-title">Workspaces</div>
        <div className="workspace-list">
          {workspaces.map((workspace) => (
            <button
              key={workspace.id}
              className={cls('workspace-row', workspace.id === activeWorkspace.id && 'active')}
              onClick={() => selectWorkspace(workspace)}
            >
              <span className="workspace-topline">
                <span>{workspace.name}</span>
                {workspace.unread > 0 && <span className="badge">{workspace.unread}</span>}
              </span>
              <span className="workspace-meta">{workspace.branch} · {workspace.ports.map((p) => `:${p}`).join(' ')}</span>
              <span className="workspace-latest">{workspace.latest}</span>
            </button>
          ))}
        </div>
        <div className="system-card">
          <span className="dot online" />
          <div>
            <strong>Scryer API</strong>
            <span>127.0.0.1:43210 · mock stream</span>
          </div>
        </div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <div className="crumbs">
            <span>{activeWorkspace.repo}</span>
            <strong>{activeWorkspace.name}</strong>
            <em>{activeWorkspace.cwd}</em>
          </div>
          <div className="topbar-actions">
            <button className="ghost-button" onClick={() => setView('commands')}>Commands</button>
            <button className="primary-button" onClick={() => setView('inbox')}>Inbox {unreadTotal}</button>
          </div>
        </header>

        {view === 'workspace' && (
          <section className="workspace-stage" aria-label="Workspace panes">
            <div className="pane-grid">
              {activeWorkspace.panes.map((pane) => (
                <PaneCard
                  key={pane.id}
                  pane={pane}
                  selected={pane.id === activePane.id}
                  onSelect={() => setActivePaneId(pane.id)}
                />
              ))}
            </div>
            <aside className="inspector" aria-label="Active pane inspector">
              <div className="inspector-heading">
                <span className={cls('status-pill', activePane.status)}>{statusLabel[activePane.status]}</span>
                <h2>{activePane.title}</h2>
                <p>{activePane.subtitle}</p>
              </div>
              <dl className="metadata-list">
                <div><dt>Kind</dt><dd>{activePane.kind}</dd></div>
                <div><dt>Workspace</dt><dd>{activeWorkspace.name}</dd></div>
                <div><dt>Branch</dt><dd>{activeWorkspace.branch}</dd></div>
                <div><dt>Ports</dt><dd>{activeWorkspace.ports.map((p) => `:${p}`).join(', ')}</dd></div>
              </dl>
              <div className="action-stack">
                <button className="soft-button">Split right</button>
                <button className="soft-button">Split down</button>
                <button className="ghost-button">Focus pane</button>
              </div>
            </aside>
          </section>
        )}

        {view === 'inbox' && <Inbox onJump={jumpTo} />}
        {view === 'commands' && <CommandPalette />}
      </main>

      <nav className="mobile-dock" aria-label="Mobile navigation">
        <button className={view === 'workspace' ? 'active' : ''} onClick={() => setView('workspace')}>Panes</button>
        <button onClick={() => setActivePaneId(activeWorkspace.panes[(activeWorkspace.panes.findIndex((p) => p.id === activePane.id) + 1) % activeWorkspace.panes.length].id)}>Next</button>
        <button className={view === 'inbox' ? 'active' : ''} onClick={() => setView('inbox')}>Inbox</button>
        <button className={view === 'commands' ? 'active' : ''} onClick={() => setView('commands')}>Cmd</button>
      </nav>
    </div>
  );
}

function PaneCard({ pane, selected, onSelect }: { pane: PaneModel; selected: boolean; onSelect: () => void }) {
  return (
    <article className={cls('pane-card', selected && 'selected', pane.status === 'needs-input' && 'attention')} onClick={onSelect} tabIndex={0}>
      <header className="pane-header">
        <div>
          <span className="pane-kind">{pane.kind}</span>
          <h3>{pane.title}</h3>
        </div>
        <span className={cls('status-dot', pane.status)} title={statusLabel[pane.status]} />
      </header>
      {pane.kind === 'browser' ? <BrowserMock pane={pane} /> : <TerminalMock pane={pane} />}
    </article>
  );
}

function TerminalMock({ pane }: { pane: PaneModel }) {
  return (
    <div className="terminal-pane">
      {pane.command && <div className="terminal-command">$ {pane.command}</div>}
      {(pane.output ?? []).map((line, index) => (
        <div key={`${line}-${index}`}><span className="prompt">›</span>{line}</div>
      ))}
      <div className="terminal-cursor"><span className="prompt">›</span><span className="cursor" /> awaiting event stream</div>
      <div className="terminal-keys" aria-label="Mobile terminal shortcuts">
        {['Esc', 'Ctrl', 'Tab', '↑', '↓'].map((key) => <button key={key}>{key}</button>)}
      </div>
    </div>
  );
}

function BrowserMock({ pane }: { pane: PaneModel }) {
  return (
    <div className="browser-pane">
      <div className="browser-bar"><span /> <span /> <span /> <strong>{pane.url}</strong></div>
      <div className="browser-canvas">
        <div className="preview-card">
          <span>Live preview pane</span>
          <strong>{pane.subtitle}</strong>
          <p>Dev-server/browser surfaces dock beside terminals on desktop and become focused panes on mobile.</p>
        </div>
      </div>
    </div>
  );
}

function Inbox({ onJump }: { onJump: (workspaceId: string, paneId: string) => void }) {
  return (
    <section className="panel-page">
      <div className="page-heading">
        <span className="eyebrow">Attention</span>
        <h2>Notification inbox</h2>
        <p>Everything that needs human input, across agents and panes.</p>
      </div>
      <div className="notification-list">
        {notifications.map((notification) => (
          <button key={notification.id} className="notification-row" onClick={() => onJump(notification.workspaceId, notification.paneId)}>
            <span className="attention-ring" />
            <span><strong>{notification.title}</strong><em>{notification.workspace} · {notification.body}</em></span>
            <b>Jump</b>
          </button>
        ))}
      </div>
    </section>
  );
}

function CommandPalette() {
  const commands = ['Split right', 'Split down', 'Focus next pane', 'Open port in browser pane', 'Mark pane read', 'Create terminal session'];
  return (
    <section className="panel-page">
      <div className="page-heading">
        <span className="eyebrow">Actions</span>
        <h2>Command palette</h2>
        <p>Typed action registry now; scriptable HTTP/WebSocket API later.</p>
      </div>
      <div className="command-box">Type a command or choose one below</div>
      <div className="command-list">
        {commands.map((command) => <button key={command}>{command}<span>⌘</span></button>)}
      </div>
    </section>
  );
}
