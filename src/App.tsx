import { useEffect, useMemo, useRef, useState } from 'react';
import { CommandPalette, type CommandAction } from './CommandPalette';
import { TerminalPane } from './TerminalPane';

type PaneModel = {
  id: string;
  title: string;
  createdAt: number;
};

type WorkspaceModel = {
  id: string;
  name: string;
  color: string;
  cwdLabel: string;
  branchLabel: string;
  layout: 'row' | 'column';
  panes: PaneModel[];
  activePaneId: string;
};

const repoLabel = 'repos/scryer-cmux';
const workspaceColors = [
  { name: 'Amber', value: '#E5C07B' },
  { name: 'Blue', value: '#61AFEF' },
  { name: 'Green', value: '#98C379' },
  { name: 'Cyan', value: '#56B6C2' },
  { name: 'Purple', value: '#C678DD' },
  { name: 'Red', value: '#E06C75' },
  { name: 'Gray', value: '#7F8794' },
];
const API_BASE = `http://${window.location.hostname || '127.0.0.1'}:${import.meta.env.VITE_SCRYER_CMUX_API_PORT ?? '43220'}`;

type AppState = {
  workspaces: WorkspaceModel[];
  activeWorkspaceId: string;
  hostName?: string;
};

function makeId(prefix: string) {
  return `${prefix}-${crypto.randomUUID()}`;
}

function makePane(index: number): PaneModel {
  return {
    id: makeId('pane'),
    title: `Terminal ${index}`,
    createdAt: Date.now(),
  };
}

function makeWorkspace(index: number): WorkspaceModel {
  const pane = makePane(1);
  return {
    id: makeId('workspace'),
    name: index === 1 ? 'smux' : `workspace ${index}`,
    color: workspaceColors[(index - 1) % workspaceColors.length].value,
    cwdLabel: repoLabel,
    branchLabel: 'main',
    layout: 'row',
    panes: [pane],
    activePaneId: pane.id,
  };
}

export function App() {
  const initialWorkspace = useMemo(() => makeWorkspace(1), []);
  const [workspaces, setWorkspaces] = useState<WorkspaceModel[]>(() => [initialWorkspace]);
  const [activeWorkspaceId, setActiveWorkspaceId] = useState(() => initialWorkspace.id);
  const [draggedWorkspaceId, setDraggedWorkspaceId] = useState<string | null>(null);
  const [renamingWorkspaceId, setRenamingWorkspaceId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState('');
  const [stateStatus, setStateStatus] = useState<'loading' | 'synced' | 'offline'>('loading');
  const [navCollapsed, setNavCollapsed] = useState(() => localStorage.getItem('smux-nav-collapsed') === 'true');
  const [hostName, setHostName] = useState('smux');
  const [terminalFocusToken, setTerminalFocusToken] = useState(0);
  const hasLoadedServerState = useRef(false);

  const stateReady = stateStatus !== 'loading';
  const activeWorkspace = workspaces.find((workspace) => workspace.id === activeWorkspaceId) ?? workspaces[0];
  const activePane = activeWorkspace.panes.find((pane) => pane.id === activeWorkspace.activePaneId) ?? activeWorkspace.panes[0];

  useEffect(() => {
    localStorage.setItem('smux-nav-collapsed', String(navCollapsed));
  }, [navCollapsed]);

  useEffect(() => {
    let cancelled = false;
    fetch(`${API_BASE}/api/state`)
      .then((response) => {
        if (!response.ok) throw new Error(`state load failed: ${response.status}`);
        return response.json() as Promise<AppState>;
      })
      .then((state) => {
        if (cancelled) return;
        setWorkspaces(state.workspaces);
        setActiveWorkspaceId(state.activeWorkspaceId);
        if (state.hostName) setHostName(state.hostName);
        hasLoadedServerState.current = true;
        setStateStatus('synced');
      })
      .catch(() => {
        if (cancelled) return;
        hasLoadedServerState.current = true;
        setStateStatus('offline');
      });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    if (!hasLoadedServerState.current) return;
    fetch(`${API_BASE}/api/state`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ workspaces, activeWorkspaceId }),
      keepalive: true,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`state save failed: ${response.status}`);
        return response.json() as Promise<AppState>;
      })
      .then((state) => {
        if (state.hostName) setHostName(state.hostName);
        setStateStatus('synced');
      })
      .catch(() => setStateStatus('offline'));
  }, [activeWorkspaceId, workspaces]);

  useEffect(() => {
    function flushState() {
      if (!hasLoadedServerState.current) return;
      const payload = JSON.stringify({ workspaces, activeWorkspaceId });
      if (navigator.sendBeacon) {
        navigator.sendBeacon(`${API_BASE}/api/state`, new Blob([payload], { type: 'application/json' }));
        return;
      }
      fetch(`${API_BASE}/api/state`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: payload,
        keepalive: true,
      }).catch(() => {});
    }

    window.addEventListener('pagehide', flushState);
    return () => window.removeEventListener('pagehide', flushState);
  }, [activeWorkspaceId, workspaces]);

  function updateWorkspace(workspaceId: string, updater: (workspace: WorkspaceModel) => WorkspaceModel) {
    setWorkspaces((current) => current.map((workspace) => (workspace.id === workspaceId ? updater(workspace) : workspace)));
  }

  function closeServerSession(paneId: string) {
    fetch(`${API_BASE}/api/sessions/${encodeURIComponent(paneId)}`, { method: 'DELETE' }).catch(() => {
      setStateStatus('offline');
    });
  }

  function focusActiveTerminalSoon() {
    window.setTimeout(() => setTerminalFocusToken((token) => token + 1), 0);
    window.setTimeout(() => setTerminalFocusToken((token) => token + 1), 120);
  }

  function activateWorkspace(workspaceId: string) {
    setActiveWorkspaceId(workspaceId);
    focusActiveTerminalSoon();
  }

  function createWorkspace() {
    setWorkspaces((current) => {
      const workspace = makeWorkspace(current.length + 1);
      setActiveWorkspaceId(workspace.id);
      focusActiveTerminalSoon();
      return [...current, workspace];
    });
  }

  function closeWorkspace(workspaceId = activeWorkspaceId) {
    setWorkspaces((current) => {
      const closingWorkspace = current.find((workspace) => workspace.id === workspaceId);
      closingWorkspace?.panes.forEach((pane) => closeServerSession(pane.id));

      if (current.length === 1) {
        const replacement = makeWorkspace(1);
        setActiveWorkspaceId(replacement.id);
        return [replacement];
      }

      const closingIndex = current.findIndex((workspace) => workspace.id === workspaceId);
      const next = current.filter((workspace) => workspace.id !== workspaceId);
      if (workspaceId === activeWorkspaceId) {
        const nextWorkspace = next[Math.max(0, closingIndex - 1)] ?? next[0];
        setActiveWorkspaceId(nextWorkspace.id);
      }
      return next;
    });
  }

  function openRenameWorkspace(workspaceId = activeWorkspaceId) {
    const workspace = workspaces.find((item) => item.id === workspaceId);
    if (!workspace) return;
    setRenamingWorkspaceId(workspace.id);
    setRenameDraft(workspace.name);
  }

  function submitRenameWorkspace() {
    if (!renamingWorkspaceId) return;
    const nextName = renameDraft.trim();
    if (nextName) updateWorkspace(renamingWorkspaceId, (item) => ({ ...item, name: nextName }));
    setRenamingWorkspaceId(null);
    setRenameDraft('');
  }

  function cancelRenameWorkspace() {
    setRenamingWorkspaceId(null);
    setRenameDraft('');
  }

  function setWorkspaceColor(color: string, workspaceId = activeWorkspaceId) {
    updateWorkspace(workspaceId, (workspace) => ({ ...workspace, color }));
  }

  function duplicateWorkspace(workspaceId = activeWorkspaceId) {
    const workspace = workspaces.find((item) => item.id === workspaceId);
    if (!workspace) return;
    const pane = makePane(1);
    const duplicate: WorkspaceModel = {
      ...workspace,
      id: makeId('workspace'),
      name: `${workspace.name} copy`,
      panes: [pane],
      activePaneId: pane.id,
    };
    setWorkspaces((current) => {
      const sourceIndex = current.findIndex((item) => item.id === workspaceId);
      const next = [...current];
      next.splice(sourceIndex + 1, 0, duplicate);
      return next;
    });
    setActiveWorkspaceId(duplicate.id);
    focusActiveTerminalSoon();
  }

  function moveWorkspace(workspaceId: string, direction: -1 | 1) {
    setWorkspaces((current) => {
      const index = current.findIndex((workspace) => workspace.id === workspaceId);
      const nextIndex = index + direction;
      if (index < 0 || nextIndex < 0 || nextIndex >= current.length) return current;
      const next = [...current];
      const [workspace] = next.splice(index, 1);
      next.splice(nextIndex, 0, workspace);
      return next;
    });
  }

  function reorderWorkspace(sourceId: string, targetId: string) {
    if (sourceId === targetId) return;
    setWorkspaces((current) => {
      const sourceIndex = current.findIndex((workspace) => workspace.id === sourceId);
      const targetIndex = current.findIndex((workspace) => workspace.id === targetId);
      if (sourceIndex < 0 || targetIndex < 0) return current;
      const next = [...current];
      const [workspace] = next.splice(sourceIndex, 1);
      next.splice(targetIndex, 0, workspace);
      return next;
    });
  }

  function splitPane(direction: WorkspaceModel['layout']) {
    updateWorkspace(activeWorkspaceId, (workspace) => {
      const pane = makePane(workspace.panes.length + 1);
      return {
        ...workspace,
        layout: direction,
        panes: [...workspace.panes, pane],
        activePaneId: pane.id,
      };
    });
    focusActiveTerminalSoon();
  }

  function closePane(paneId = activePane?.id) {
    if (!paneId) return;
    updateWorkspace(activeWorkspaceId, (workspace) => {
      if (workspace.panes.length === 1) return workspace;
      closeServerSession(paneId);
      const closingIndex = workspace.panes.findIndex((pane) => pane.id === paneId);
      const panes = workspace.panes.filter((pane) => pane.id !== paneId);
      const nextActivePane = paneId === workspace.activePaneId
        ? panes[Math.max(0, closingIndex - 1)] ?? panes[0]
        : panes.find((pane) => pane.id === workspace.activePaneId) ?? panes[0];
      return { ...workspace, panes, activePaneId: nextActivePane.id };
    });
  }

  function setActivePane(paneId: string, workspaceId = activeWorkspaceId) {
    updateWorkspace(workspaceId, (workspace) => ({ ...workspace, activePaneId: paneId }));
    focusActiveTerminalSoon();
  }

  const actions = useMemo<CommandAction[]>(() => {
    const workspaceActions = workspaces.map((workspace) => ({
      id: `switch-workspace-${workspace.id}`,
      icon: workspace.id === activeWorkspaceId ? '●' : '◌',
      label: workspace.name,
      hint: `${workspace.panes.length} pane${workspace.panes.length === 1 ? '' : 's'}`,
      depth: 1,
      onSelect: () => activateWorkspace(workspace.id),
    }));

    const paneActions = activeWorkspace.panes.map((pane, index) => ({
      id: `switch-pane-${pane.id}`,
      icon: pane.id === activeWorkspace.activePaneId ? '●' : '◌',
      label: pane.title,
      hint: `pane ${index + 1}`,
      depth: 1,
      onSelect: () => setActivePane(pane.id),
    }));

    const colorActions = workspaceColors.map((color) => ({
      id: `workspace-color-${color.name}`,
      icon: activeWorkspace.color === color.value ? '●' : '■',
      label: `Set workspace color: ${color.name}`,
      hint: activeWorkspace.color === color.value ? 'current' : undefined,
      depth: 1,
      onSelect: () => setWorkspaceColor(color.value),
    }));

    return [
      { id: 'workspace-heading', separator: true, icon: '', label: '' },
      { id: 'new-workspace', icon: '+', label: 'New workspace', hint: 'create', onSelect: createWorkspace },
      { id: 'rename-workspace', icon: '✎', label: 'Rename workspace', hint: activeWorkspace.name, onSelect: () => openRenameWorkspace() },
      { id: 'duplicate-workspace', icon: '⧉', label: 'Duplicate workspace', hint: activeWorkspace.name, onSelect: () => duplicateWorkspace() },
      { id: 'move-workspace-up', icon: '↑', label: 'Move workspace up', hint: activeWorkspace.name, onSelect: () => moveWorkspace(activeWorkspaceId, -1) },
      { id: 'move-workspace-down', icon: '↓', label: 'Move workspace down', hint: activeWorkspace.name, onSelect: () => moveWorkspace(activeWorkspaceId, 1) },
      { id: 'close-workspace', icon: '×', label: 'Close workspace', hint: activeWorkspace.name, onSelect: () => closeWorkspace() },
      { id: 'workspace-color-heading', separator: true, icon: '', label: '' },
      ...colorActions,
      { id: 'switch-workspace-heading', separator: true, icon: '', label: '' },
      ...workspaceActions,
      { id: 'pane-heading', separator: true, icon: '', label: '' },
      { id: 'split-right', icon: '▣', label: 'Split pane right', hint: 'side by side', onSelect: () => splitPane('row') },
      { id: 'split-down', icon: '▤', label: 'Split pane down', hint: 'stacked', onSelect: () => splitPane('column') },
      ...(activeWorkspace.panes.length > 1
        ? [{ id: 'close-pane', icon: '×', label: 'Close active pane', hint: activePane?.title, onSelect: () => closePane() }]
        : []),
      { id: 'switch-pane-heading', separator: true, icon: '', label: '' },
      ...paneActions,
    ];
  }, [activePane?.title, activeWorkspace, activeWorkspaceId, workspaces]);

  return (
    <div className={`cmux-shell${navCollapsed ? ' nav-collapsed' : ''}`}>
      <aside className="workspace-sidebar" aria-label="Workspaces">
        <div className="app-title-row">
          <div className="app-title" title={hostName}>{hostName}</div>
          <div className="nav-actions">
            <button
              className="nav-toggle"
              type="button"
              onClick={() => setNavCollapsed((value) => !value)}
              title={navCollapsed ? 'Expand workspace nav' : 'Collapse workspace nav'}
              aria-label={navCollapsed ? 'Expand workspace nav' : 'Collapse workspace nav'}
              aria-expanded={!navCollapsed}
            >
              <svg className="nav-toggle-icon" viewBox="0 0 16 16" aria-hidden="true">
                <rect x="2" y="3" width="12" height="10" rx="1.5" />
                <path d="M6 3v10" />
                <path className="nav-toggle-arrow" d={navCollapsed ? 'M9 6l2 2-2 2' : 'M11 6L9 8l2 2'} />
              </svg>
            </button>
          </div>
        </div>

        <div className="workspace-list">
          {workspaces.map((workspace) => (
            <div
              key={workspace.id}
              className={`workspace-tab${workspace.id === activeWorkspaceId ? ' active' : ''}${workspace.id === draggedWorkspaceId ? ' dragging' : ''}`}
              title={workspace.name}
              role="button"
              tabIndex={0}
              draggable
              onDragStart={(event) => {
                setDraggedWorkspaceId(workspace.id);
                event.dataTransfer.effectAllowed = 'move';
                event.dataTransfer.setData('text/plain', workspace.id);
              }}
              onDragOver={(event) => {
                event.preventDefault();
                event.dataTransfer.dropEffect = 'move';
              }}
              onDrop={(event) => {
                event.preventDefault();
                const sourceId = event.dataTransfer.getData('text/plain') || draggedWorkspaceId;
                if (sourceId) reorderWorkspace(sourceId, workspace.id);
                setDraggedWorkspaceId(null);
              }}
              onDragEnd={() => setDraggedWorkspaceId(null)}
              onDoubleClick={() => openRenameWorkspace(workspace.id)}
              onClick={() => activateWorkspace(workspace.id)}
              onKeyDown={(event) => {
                if (event.key === 'Enter' || event.key === ' ') {
                  event.preventDefault();
                  activateWorkspace(workspace.id);
                }
              }}
            >
              <div className="workspace-tab-topline">
                <span className="workspace-color-chip" style={{ backgroundColor: workspace.color }} aria-hidden="true" />
                <span className="tab-title">{workspace.name}</span>
                <button
                  className="workspace-close"
                  type="button"
                  title={`Close ${workspace.name}`}
                  aria-label={`Close ${workspace.name}`}
                  onClick={(event) => {
                    event.stopPropagation();
                    closeWorkspace(workspace.id);
                  }}
                >
                  ×
                </button>
              </div>
              <span className="tab-meta">{workspace.branchLabel} · {workspace.panes.length} pane{workspace.panes.length === 1 ? '' : 's'}</span>
              <span className="tab-note">{workspace.cwdLabel}</span>
            </div>
          ))}
        </div>
      </aside>

      <main className="workspace-main">
        <header className="toolbar">
          <div className="toolbar-left">
            <strong>{activeWorkspace.name}</strong>
            <span>{activeWorkspace.cwdLabel}</span>
            <span>{activeWorkspace.branchLabel}</span>
            <span>{activePane?.title}</span>
            <span>{stateStatus === 'synced' ? 'server state' : stateStatus}</span>
          </div>
          <div className="toolbar-actions">
            <span className="shortcut-hint">⌘K</span>
          </div>
        </header>

        <section className="terminal-stage">
          {!stateReady ? (
            <div className="terminal-loading">Loading server workspace state…</div>
          ) : workspaces.map((workspace) => (
            <div
              key={workspace.id}
              className={`workspace-surface${workspace.id === activeWorkspaceId ? ' active' : ''}`}
              aria-hidden={workspace.id !== activeWorkspaceId}
            >
              <div className={`pane-grid ${workspace.layout}`}>
                {workspace.panes.map((pane) => {
                  const isActive = workspace.id === activeWorkspaceId && pane.id === workspace.activePaneId;
                  return (
                    <article
                      key={pane.id}
                      className={`pane terminal-pane-card${isActive ? ' active' : ''}`}
                      onMouseDown={() => {
                        activateWorkspace(workspace.id);
                        setActivePane(pane.id, workspace.id);
                      }}
                    >
                      <div className="pane-titlebar">
                        <span>{pane.title}</span>
                        <div className="pane-titlebar-actions">
                          <em>{isActive ? 'active shell' : 'local shell'}</em>
                          <button type="button" title="Split right" onClick={() => splitPane('row')}>▣</button>
                          <button type="button" title="Split down" onClick={() => splitPane('column')}>▤</button>
                          {workspace.panes.length > 1 ? <button type="button" title="Close pane" onClick={() => closePane(pane.id)}>×</button> : null}
                        </div>
                      </div>
                      <TerminalPane paneId={pane.id} active={isActive} focusToken={isActive ? terminalFocusToken : 0} />
                    </article>
                  );
                })}
              </div>
            </div>
          ))}
        </section>
      </main>

      <CommandPalette actions={actions} />

      {renamingWorkspaceId ? (
        <div className="modal-layer" role="presentation" onMouseDown={cancelRenameWorkspace}>
          <form
            className="rename-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="rename-workspace-title"
            onMouseDown={(event) => event.stopPropagation()}
            onSubmit={(event) => {
              event.preventDefault();
              submitRenameWorkspace();
            }}
          >
            <div className="modal-titlebar">
              <div>
                <h2 id="rename-workspace-title">Rename workspace</h2>
                <p>Give this terminal workspace a short, memorable name.</p>
              </div>
              <button type="button" className="modal-close" aria-label="Cancel rename" onClick={cancelRenameWorkspace}>×</button>
            </div>
            <label className="field-label" htmlFor="workspace-name-input">Workspace name</label>
            <input
              id="workspace-name-input"
              className="rename-input"
              value={renameDraft}
              autoFocus
              onChange={(event) => setRenameDraft(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Escape') {
                  event.preventDefault();
                  cancelRenameWorkspace();
                }
              }}
            />
            <div className="modal-actions">
              <button type="button" className="ghost-button" onClick={cancelRenameWorkspace}>Cancel</button>
              <button type="submit" className="create-button" disabled={!renameDraft.trim()}>Rename</button>
            </div>
          </form>
        </div>
      ) : null}
    </div>
  );
}
