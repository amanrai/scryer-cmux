import type { CSSProperties } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CommandPalette } from './CommandPalette';
import { API_BASE, DEFAULT_FONT_SIZE } from './constants';
import { ColorPicker } from './components/ColorPicker';
import { CommandInputModal } from './components/CommandInputModal';
import { HostBar } from './components/HostBar';
import { RenameModal } from './components/RenameModal';
import { TerminalStage } from './components/TerminalStage';
import { WorkspaceSidebar } from './components/WorkspaceSidebar';
import { WorkspaceContextMenu } from './components/WorkspaceContextMenu';
import { useCommandActions } from './hooks/useCommandActions';
import { useServerStateSync } from './hooks/useServerStateSync';
import type { TerminalPaneApi } from './TerminalPane';
import type { ColorPickerState, PaneModel, PaneStatus, RenameTarget, WorkspaceMenuState, WorkspaceModel } from './types';
import { makePane, makeWorkspace, makeId } from './workspaceModel';

function cssVars(vars: Record<string, string>) {
  return vars as CSSProperties;
}

function loadPaneFontSizes() {
  try {
    return JSON.parse(localStorage.getItem('smux-pane-fontsize') ?? '{}') as Record<string, number>;
  } catch {
    return {};
  }
}

export function App() {
  const initialWorkspace = useMemo(() => makeWorkspace(1), []);
  const [workspaces, setWorkspaces] = useState<WorkspaceModel[]>(() => [initialWorkspace]);
  const [activeWorkspaceId, setActiveWorkspaceId] = useState(() => initialWorkspace.id);
  const [draggedWorkspaceId, setDraggedWorkspaceId] = useState<string | null>(null);
  const [renameTarget, setRenameTarget] = useState<RenameTarget | null>(null);
  const [renameDraft, setRenameDraft] = useState('');
  const [stateStatus, setStateStatus] = useState<'loading' | 'synced' | 'offline'>('loading');
  const [navCollapsed, setNavCollapsed] = useState(() => localStorage.getItem('smux-nav-collapsed') === 'true');
  const [hostName, setHostName] = useState('smux');
  const [terminalFocusToken, setTerminalFocusToken] = useState(0);
  const [paneStatus, setPaneStatus] = useState<Record<string, PaneStatus>>({});
  const [paneInteractionState, setPaneInteractionState] = useState<Record<string, { hasProducer: boolean; hasPending: boolean }>>({});
  const [paneFontSize, setPaneFontSize] = useState<Record<string, number>>(loadPaneFontSizes);
  const [colorPicker, setColorPicker] = useState<ColorPickerState | null>(null);
  const [workspaceMenu, setWorkspaceMenu] = useState<WorkspaceMenuState | null>(null);
  const [commandInput, setCommandInput] = useState<{ paneId: string; paneTitle: string; recentLines: string[] } | null>(null);
  const paneApis = useRef<Record<string, TerminalPaneApi>>({});
  const hasLoadedServerState = useRef(false);

  const stateReady = stateStatus !== 'loading';
  const activeWorkspace = workspaces.find((workspace) => workspace.id === activeWorkspaceId) ?? workspaces[0];
  const activePane = activeWorkspace.panes.find((pane) => pane.id === activeWorkspace.activePaneId) ?? activeWorkspace.panes[0];

  useEffect(() => {
    localStorage.setItem('smux-nav-collapsed', String(navCollapsed));
  }, [navCollapsed]);

  useEffect(() => {
    localStorage.setItem('smux-pane-fontsize', JSON.stringify(paneFontSize));
  }, [paneFontSize]);

  useServerStateSync({
    workspaces,
    activeWorkspaceId,
    loadedRef: hasLoadedServerState,
    setWorkspaces,
    setActiveWorkspaceId,
    setHostName,
    setStateStatus,
  });

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && !event.shiftKey && !event.altKey && event.key.toLowerCase() === 't') {
        event.preventDefault();
        splitPane('row');
      }
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [activeWorkspaceId]);

  function updateWorkspace(workspaceId: string, updater: (workspace: WorkspaceModel) => WorkspaceModel) {
    setWorkspaces((current) => current.map((workspace) => (workspace.id === workspaceId ? updater(workspace) : workspace)));
  }

  function closeServerSession(paneId: string) {
    fetch(`${API_BASE}/api/sessions/${encodeURIComponent(paneId)}`, { method: 'DELETE' }).catch(() => setStateStatus('offline'));
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
      current.find((workspace) => workspace.id === workspaceId)?.panes.forEach((pane) => closeServerSession(pane.id));
      if (current.length === 1) {
        const replacement = makeWorkspace(1);
        setActiveWorkspaceId(replacement.id);
        return [replacement];
      }
      const closingIndex = current.findIndex((workspace) => workspace.id === workspaceId);
      const next = current.filter((workspace) => workspace.id !== workspaceId);
      if (workspaceId === activeWorkspaceId) setActiveWorkspaceId((next[Math.max(0, closingIndex - 1)] ?? next[0]).id);
      return next;
    });
  }

  function openRenameWorkspace(workspaceId = activeWorkspaceId) {
    const workspace = workspaces.find((item) => item.id === workspaceId);
    if (!workspace) return;
    setRenameTarget({ kind: 'workspace', id: workspace.id });
    setRenameDraft(workspace.name);
  }

  function openRenamePane(pane: PaneModel) {
    setRenameTarget({ kind: 'pane', id: pane.id });
    setRenameDraft(pane.title);
  }

  function submitRename() {
    if (!renameTarget) return;
    const nextName = renameDraft.trim();
    if (nextName && renameTarget.kind === 'workspace') updateWorkspace(renameTarget.id, (workspace) => ({ ...workspace, name: nextName }));
    if (nextName && renameTarget.kind === 'pane') {
      updateWorkspace(activeWorkspaceId, (workspace) => ({
        ...workspace,
        panes: workspace.panes.map((pane) => (pane.id === renameTarget.id ? { ...pane, title: nextName } : pane)),
      }));
    }
    setRenameTarget(null);
    setRenameDraft('');
  }

  function setWorkspaceColor(color: string, workspaceId = activeWorkspaceId) {
    updateWorkspace(workspaceId, (workspace) => ({ ...workspace, color }));
  }

  function duplicateWorkspace(workspaceId = activeWorkspaceId) {
    const workspace = workspaces.find((item) => item.id === workspaceId);
    if (!workspace) return;
    const pane = makePane(1);
    const duplicate: WorkspaceModel = { ...workspace, id: makeId('workspace'), name: `${workspace.name} copy`, panes: [pane], activePaneId: pane.id };
    setWorkspaces((current) => {
      const next = [...current];
      next.splice(current.findIndex((item) => item.id === workspaceId) + 1, 0, duplicate);
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

  function moveWorkspaceToEdge(workspaceId: string, edge: 'top' | 'bottom') {
    setWorkspaces((current) => {
      const index = current.findIndex((workspace) => workspace.id === workspaceId);
      if (index < 0) return current;
      const next = [...current];
      const [workspace] = next.splice(index, 1);
      if (edge === 'top') next.unshift(workspace);
      else next.push(workspace);
      return next;
    });
  }

  function closeOtherWorkspaces(workspaceId: string) {
    setWorkspaces((current) => {
      const kept = current.find((workspace) => workspace.id === workspaceId);
      if (!kept) return current;
      current.forEach((workspace) => {
        if (workspace.id !== workspaceId) workspace.panes.forEach((pane) => closeServerSession(pane.id));
      });
      setActiveWorkspaceId(workspaceId);
      return [kept];
    });
  }

  function closeWorkspacesBelow(workspaceId: string) {
    setWorkspaces((current) => {
      const index = current.findIndex((workspace) => workspace.id === workspaceId);
      if (index < 0) return current;
      current.slice(index + 1).forEach((workspace) => workspace.panes.forEach((pane) => closeServerSession(pane.id)));
      const next = current.slice(0, index + 1);
      if (!next.some((workspace) => workspace.id === activeWorkspaceId)) setActiveWorkspaceId(workspaceId);
      return next;
    });
  }

  function closeWorkspacesAbove(workspaceId: string) {
    setWorkspaces((current) => {
      const index = current.findIndex((workspace) => workspace.id === workspaceId);
      if (index <= 0) return current;
      current.slice(0, index).forEach((workspace) => workspace.panes.forEach((pane) => closeServerSession(pane.id)));
      const next = current.slice(index);
      if (!next.some((workspace) => workspace.id === activeWorkspaceId)) setActiveWorkspaceId(workspaceId);
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
      return { ...workspace, layout: direction, panes: [...workspace.panes, pane], activePaneId: pane.id };
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
      const nextActivePane = paneId === workspace.activePaneId ? panes[Math.max(0, closingIndex - 1)] ?? panes[0] : panes.find((pane) => pane.id === workspace.activePaneId) ?? panes[0];
      return { ...workspace, panes, activePaneId: nextActivePane.id };
    });
  }

  function setActivePane(paneId: string, workspaceId = activeWorkspaceId) {
    updateWorkspace(workspaceId, (workspace) => ({ ...workspace, activePaneId: paneId }));
    focusActiveTerminalSoon();
  }

  function adjustPaneFontSize(paneId: string, delta: number) {
    setPaneFontSize((current) => ({ ...current, [paneId]: Math.min(28, Math.max(8, (current[paneId] ?? DEFAULT_FONT_SIZE) + delta)) }));
  }

  function reportPaneStatus(paneId: string, status: PaneStatus) {
    setPaneStatus((current) => (current[paneId] === status ? current : { ...current, [paneId]: status }));
  }

  const registerPaneApi = useCallback((paneId: string, api: TerminalPaneApi | null) => {
    if (api) paneApis.current[paneId] = api;
    else delete paneApis.current[paneId];
  }, []);

  function openCommandInput(pane: PaneModel) {
    const recentLines = paneApis.current[pane.id]?.getRecentLines(200) ?? [];
    setCommandInput({ paneId: pane.id, paneTitle: pane.title, recentLines });
  }

  function openPaneInteraction(paneId: string) {
    paneApis.current[paneId]?.openInteraction();
  }

  function updatePaneInteractionState(paneId: string, next: { hasProducer: boolean; hasPending: boolean }) {
    setPaneInteractionState((current) => {
      const existing = current[paneId];
      if (existing?.hasProducer === next.hasProducer && existing?.hasPending === next.hasPending) return current;
      return { ...current, [paneId]: next };
    });
  }

  function sendCommandInput(value: string) {
    if (!commandInput) return;
    paneApis.current[commandInput.paneId]?.sendInput(`${value}\r`);
    setCommandInput(null);
  }

  const actions = useCommandActions({
    workspaces,
    activeWorkspace,
    activeWorkspaceId,
    activePane,
    activateWorkspace,
    createWorkspace,
    openRenameWorkspace,
    duplicateWorkspace,
    moveWorkspace,
    closeWorkspace,
    splitPane,
    openRenamePane,
    closePane,
  });

  return (
    <div className={`cmux-shell${navCollapsed ? ' nav-collapsed' : ''}`} style={cssVars({ '--accent': activeWorkspace.color })}>
      <HostBar hostName={hostName} stateStatus={stateStatus} />
      <WorkspaceSidebar
        workspaces={workspaces}
        activeWorkspaceId={activeWorkspaceId}
        draggedWorkspaceId={draggedWorkspaceId}
        navCollapsed={navCollapsed}
        onToggleCollapsed={() => setNavCollapsed((value) => !value)}
        onCreateWorkspace={createWorkspace}
        onActivateWorkspace={activateWorkspace}
        onCloseWorkspace={closeWorkspace}
        onRenameWorkspace={openRenameWorkspace}
        onReorderWorkspace={reorderWorkspace}
        onSetDraggedWorkspaceId={setDraggedWorkspaceId}
        onSetColorPicker={setColorPicker}
        onOpenContextMenu={(workspaceId, x, y) => {
          setColorPicker(null);
          setWorkspaceMenu({ workspaceId, x, y });
        }}
      />
      <TerminalStage
        stateReady={stateReady}
        hostName={hostName}
        workspaces={workspaces}
        activeWorkspaceId={activeWorkspaceId}
        paneStatus={paneStatus}
        paneFontSize={paneFontSize}
        paneInteractionState={paneInteractionState}
        terminalFocusToken={terminalFocusToken}
        onActivateWorkspace={activateWorkspace}
        onSetActivePane={setActivePane}
        onRenamePane={openRenamePane}
        onAdjustPaneFontSize={adjustPaneFontSize}
        onOpenCommandInput={openCommandInput}
        onOpenPaneInteraction={openPaneInteraction}
        onSplitPane={splitPane}
        onClosePane={closePane}
        onPaneStatus={reportPaneStatus}
        onPaneInteractionState={updatePaneInteractionState}
        onRegisterPaneApi={registerPaneApi}
      />
      <CommandPalette actions={actions} />
      {colorPicker ? <ColorPicker picker={colorPicker} workspaces={workspaces} onSetColor={setWorkspaceColor} onClose={() => setColorPicker(null)} /> : null}
      {workspaceMenu ? (
        <WorkspaceContextMenu
          menu={workspaceMenu}
          workspaces={workspaces}
          onRename={openRenameWorkspace}
          onSetColor={setWorkspaceColor}
          onMove={moveWorkspace}
          onMoveToEdge={moveWorkspaceToEdge}
          onDuplicate={duplicateWorkspace}
          onClose={closeWorkspace}
          onCloseOthers={closeOtherWorkspaces}
          onCloseBelow={closeWorkspacesBelow}
          onCloseAbove={closeWorkspacesAbove}
          onDismiss={() => setWorkspaceMenu(null)}
        />
      ) : null}
      {renameTarget ? <RenameModal target={renameTarget} draft={renameDraft} onDraftChange={setRenameDraft} onSubmit={submitRename} onCancel={() => setRenameTarget(null)} /> : null}
      {commandInput ? (
        <CommandInputModal
          paneTitle={commandInput.paneTitle}
          recentLines={commandInput.recentLines}
          onSend={sendCommandInput}
          onCancel={() => setCommandInput(null)}
        />
      ) : null}
    </div>
  );
}
