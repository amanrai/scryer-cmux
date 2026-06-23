import type { CSSProperties } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CommandPalette } from './CommandPalette';
import { API_BASE, DEFAULT_FONT_SIZE } from './constants';
import { ColorPicker } from './components/ColorPicker';
import { CommandInputModal } from './components/CommandInputModal';
import { HostBar } from './components/HostBar';
import { RenameModal } from './components/RenameModal';
import { SettingsModal } from './components/SettingsModal';
import { TerminalStage } from './components/TerminalStage';
import { WorkspaceSidebar } from './components/WorkspaceSidebar';
import { WorkspaceContextMenu } from './components/WorkspaceContextMenu';
import { useCommandActions } from './hooks/useCommandActions';
import { useServerStateSync } from './hooks/useServerStateSync';
import type { TerminalPaneApi } from './TerminalPane';
import type { BackendMachine, ColorPickerState, PaneModel, PaneStatus, RenameTarget, WorkspaceMenuState, WorkspaceModel } from './types';
import type { SmuxThemeName } from './terminal/theme';
import { machineIconClass, sanitizeMachineIconIds, type MachineIconId } from './machineIcons';
import { makePane, makeWorkspace, makeId } from './workspaceModel';

function cssVars(vars: Record<string, string>) {
  return vars as CSSProperties;
}

function loadThemeName(): SmuxThemeName {
  return localStorage.getItem('smux-theme') === 'sunlight' ? 'sunlight' : 'dark';
}

function loadPaneFontSizes() {
  try {
    return JSON.parse(localStorage.getItem('smux-pane-fontsize') ?? '{}') as Record<string, number>;
  } catch {
    return {};
  }
}

function loadInteractionsEnabled() {
  return localStorage.getItem('smux-interactions-enabled') !== 'false';
}

function loadMachineIcons() {
  try {
    const raw = JSON.parse(localStorage.getItem('smux-machine-icons') ?? '{}') as Record<string, unknown>;
    return Object.fromEntries(Object.entries(raw).map(([host, icons]) => [host, sanitizeMachineIconIds(icons)])) as Record<string, MachineIconId[]>;
  } catch {
    return {};
  }
}

type HostButtonSettings = {
  fontSize: boolean;
  interaction: boolean;
  agentUpdates: boolean;
  scryer: boolean;
  quickInputs: boolean;
};

const defaultHostButtonSettings: HostButtonSettings = {
  fontSize: true,
  interaction: true,
  agentUpdates: true,
  scryer: true,
  quickInputs: false,
};

function loadMachineNames() {
  try {
    const raw = JSON.parse(localStorage.getItem('smux-machine-names') ?? '{}') as Record<string, unknown>;
    return Object.fromEntries(Object.entries(raw).filter(([, name]) => typeof name === 'string').map(([host, name]) => [host, String(name).trim()]).filter(([, name]) => name)) as Record<string, string>;
  } catch {
    return {};
  }
}

function loadHostButtonSettings(): HostButtonSettings {
  try {
    return { ...defaultHostButtonSettings, ...JSON.parse(localStorage.getItem('smux-host-buttons') ?? '{}') };
  } catch {
    return defaultHostButtonSettings;
  }
}

function loadMachineNameColors() {
  try {
    const raw = JSON.parse(localStorage.getItem('smux-machine-name-colors') ?? '{}') as Record<string, unknown>;
    return Object.fromEntries(Object.entries(raw).filter(([, color]) => typeof color === 'string' && /^#[0-9a-f]{6}$/i.test(color))) as Record<string, string>;
  } catch {
    return {};
  }
}

function loadActiveBackendId() {
  return localStorage.getItem('amux-active-backend-id') ?? '';
}

export function App() {
  const initialWorkspace = useMemo(() => makeWorkspace(1), []);
  const [workspaces, setWorkspaces] = useState<WorkspaceModel[]>(() => [initialWorkspace]);
  const [activeWorkspaceId, setActiveWorkspaceId] = useState(() => initialWorkspace.id);
  const [draggedWorkspaceId, setDraggedWorkspaceId] = useState<string | null>(null);
  const [renameTarget, setRenameTarget] = useState<RenameTarget | null>(null);
  const [renameDraft, setRenameDraft] = useState('');
  const [stateStatus, setStateStatus] = useState<'loading' | 'synced' | 'offline'>('loading');
  const [reachableBackends, setReachableBackends] = useState<BackendMachine[]>([]);
  const [activeBackendId, setActiveBackendId] = useState(loadActiveBackendId);
  const [navCollapsed, setNavCollapsed] = useState(() => localStorage.getItem('smux-nav-collapsed') === 'true');
  const [hostName, setHostName] = useState('smux');
  const [terminalFocusToken, setTerminalFocusToken] = useState(0);
  const [paneStatus, setPaneStatus] = useState<Record<string, PaneStatus>>({});
  const [paneInteractionState, setPaneInteractionState] = useState<Record<string, { hasProducer: boolean; hasPending: boolean }>>({});
  const [paneActivityState, setPaneActivityState] = useState<Record<string, { count: number; unread: number; latestLevel?: string; latestKind?: string }>>({});
  const [themeName, setThemeName] = useState<SmuxThemeName>(loadThemeName);
  const [interactionsEnabled, setInteractionsEnabled] = useState(loadInteractionsEnabled);
  const [machineIconsByHost, setMachineIconsByHost] = useState<Record<string, MachineIconId[]>>(loadMachineIcons);
  const [machineNamesByHost, setMachineNamesByHost] = useState<Record<string, string>>(loadMachineNames);
  const [machineNameColorsByHost, setMachineNameColorsByHost] = useState<Record<string, string>>(loadMachineNameColors);
  const [hostButtonSettings, setHostButtonSettings] = useState<HostButtonSettings>(loadHostButtonSettings);
  const [paneFontSize, setPaneFontSize] = useState<Record<string, number>>(loadPaneFontSizes);
  const [colorPicker, setColorPicker] = useState<ColorPickerState | null>(null);
  const [workspaceMenu, setWorkspaceMenu] = useState<WorkspaceMenuState | null>(null);
  const [commandInput, setCommandInput] = useState<{ paneId: string; paneTitle: string; recentLines: string[] } | null>(null);
  const [settingsVisible, setSettingsVisible] = useState(false);
  const paneApis = useRef<Record<string, TerminalPaneApi>>({});
  const hasLoadedServerState = useRef(false);

  const stateReady = stateStatus !== 'loading';
  const activeWorkspace = workspaces.find((workspace) => workspace.id === activeWorkspaceId) ?? workspaces[0];
  const activePane = activeWorkspace.panes[0];
  const activePaneInteractionState = paneInteractionState[activePane.id] ?? { hasProducer: false, hasPending: false };
  const activePaneActivityState = paneActivityState[activePane.id] ?? { count: 0, unread: 0 };
  const machineCustomizationKey = activeBackendId || hostName;
  const selectedMachineIcons = machineIconsByHost[machineCustomizationKey] ?? [];
  const machineNameDraft = machineNamesByHost[machineCustomizationKey] ?? hostName;
  const displayHostName = machineNameDraft.trim() || hostName;
  const machineNameColor = machineNameColorsByHost[machineCustomizationKey];

  const loadReachableBackends = useCallback(async () => {
    try {
      const response = await fetch(`${API_BASE}/api/backends`);
      if (!response.ok) return;
      const payload = await response.json() as { backends?: BackendMachine[] };
      const reachable = (payload.backends ?? []).filter((backend) => backend.kind === 'pty' && backend.status === 'online');
      setReachableBackends(reachable);
      setActiveBackendId((current) => {
        if (current && reachable.some((backend) => backend.id === current)) return current;
        if (!reachable[0]?.id) return current;
        hasLoadedServerState.current = false;
        setStateStatus('loading');
        setHostName(reachable[0].label || reachable[0].id);
        return reachable[0].id;
      });
    } catch {}
  }, []);

  useEffect(() => {
    void loadReachableBackends();
    const timer = window.setInterval(() => { void loadReachableBackends(); }, 10_000);
    return () => window.clearInterval(timer);
  }, [loadReachableBackends]);

  useEffect(() => {
    localStorage.setItem('amux-active-backend-id', activeBackendId);
  }, [activeBackendId]);

  useEffect(() => {
    localStorage.setItem('smux-nav-collapsed', String(navCollapsed));
  }, [navCollapsed]);

  useEffect(() => {
    localStorage.setItem('smux-theme', themeName);
  }, [themeName]);

  useEffect(() => {
    localStorage.setItem('smux-interactions-enabled', String(interactionsEnabled));
  }, [interactionsEnabled]);

  useEffect(() => {
    localStorage.setItem('smux-machine-icons', JSON.stringify(machineIconsByHost));
  }, [machineIconsByHost]);

  useEffect(() => {
    localStorage.setItem('smux-machine-names', JSON.stringify(machineNamesByHost));
  }, [machineNamesByHost]);

  useEffect(() => {
    localStorage.setItem('smux-host-buttons', JSON.stringify(hostButtonSettings));
  }, [hostButtonSettings]);

  useEffect(() => {
    localStorage.setItem('smux-machine-name-colors', JSON.stringify(machineNameColorsByHost));
  }, [machineNameColorsByHost]);

  useEffect(() => {
    localStorage.setItem('smux-pane-fontsize', JSON.stringify(paneFontSize));
  }, [paneFontSize]);

  useEffect(() => {
    const scrollableSelector = [
      '.interaction-pane-modal',
      '.activity-pane-modal',
      '.scryer-picker-modal',
      '.quick-input-modal',
      '.command-input-modal',
      '.command-context',
      '.terminal-accessory',
      '.palette',
      '.workspace-list',
    ].join(',');

    const interactiveSelector = 'button, a, input, select, textarea, [role="button"], [tabindex]';

    function preventPageTouchScroll(event: TouchEvent) {
      const target = event.target as Element | null;
      if (target?.closest(scrollableSelector)) return;
      event.preventDefault();
    }

    function preventPageTouchStart(event: TouchEvent) {
      const target = event.target as Element | null;
      if (target?.closest(scrollableSelector)) return;
      if (target?.closest(interactiveSelector)) return;
      event.preventDefault();
    }

    function lockPageScroll() {
      if (window.scrollX !== 0 || window.scrollY !== 0) window.scrollTo(0, 0);
    }

    document.addEventListener('touchstart', preventPageTouchStart, { passive: false });
    document.addEventListener('touchmove', preventPageTouchScroll, { passive: false });
    window.addEventListener('scroll', lockPageScroll, { passive: true });
    return () => {
      document.removeEventListener('touchstart', preventPageTouchStart);
      document.removeEventListener('touchmove', preventPageTouchScroll);
      window.removeEventListener('scroll', lockPageScroll);
    };
  }, []);

  useServerStateSync({
    workspaces,
    activeWorkspaceId,
    activeBackendId,
    loadedRef: hasLoadedServerState,
    setWorkspaces,
    setActiveWorkspaceId,
    setHostName,
    setStateStatus,
  });

  function updateWorkspace(workspaceId: string, updater: (workspace: WorkspaceModel) => WorkspaceModel) {
    setWorkspaces((current) => current.map((workspace) => (workspace.id === workspaceId ? updater(workspace) : workspace)));
  }

  function closeServerSession(paneId: string) {
    const path = activeBackendId ? `${API_BASE}/api/backends/${encodeURIComponent(activeBackendId)}/sessions/${encodeURIComponent(paneId)}` : `${API_BASE}/api/sessions/${encodeURIComponent(paneId)}`;
    fetch(path, { method: 'DELETE' }).catch(() => setStateStatus('offline'));
  }

  function switchBackend(backend: BackendMachine) {
    if (!backend.id || backend.id === activeBackendId) return;
    hasLoadedServerState.current = false;
    paneApis.current = {};
    setPaneStatus({});
    setPaneInteractionState({});
    setPaneActivityState({});
    setHostName(backend.label || backend.id);
    setStateStatus('loading');
    setActiveBackendId(backend.id);
    focusActiveTerminalSoon();
  }

  function focusActiveTerminalSoon() {
    window.setTimeout(() => setTerminalFocusToken((token) => token + 1), 50);
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

  function openPaneActivity(paneId: string) {
    paneApis.current[paneId]?.openActivity();
  }

  function openPaneScryerPicker(paneId: string) {
    paneApis.current[paneId]?.openScryerPicker();
  }

  function openPaneQuickInputs(paneId: string) {
    paneApis.current[paneId]?.openQuickInputs();
  }

  function updatePaneInteractionState(paneId: string, next: { hasProducer: boolean; hasPending: boolean }) {
    setPaneInteractionState((current) => {
      const existing = current[paneId];
      if (existing?.hasProducer === next.hasProducer && existing?.hasPending === next.hasPending) return current;
      return { ...current, [paneId]: next };
    });
  }

  function updatePaneActivityState(paneId: string, next: { count: number; unread: number; latestLevel?: string; latestKind?: string }) {
    setPaneActivityState((current) => {
      const existing = current[paneId];
      if (existing?.count === next.count && existing?.unread === next.unread && existing?.latestLevel === next.latestLevel && existing?.latestKind === next.latestKind) return current;
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
    openRenamePane,
  });

  const commandActions = useMemo(() => [
    { id: 'machine-heading', separator: true, icon: '', label: 'Machine' },
    ...reachableBackends.map((backend) => ({
      id: `switch-backend-${backend.id}`,
      icon: backend.id === activeBackendId ? 'fa-solid fa-circle-dot' : 'fa-solid fa-server',
      label: `Switch machine: ${backend.label}`,
      hint: backend.id === activeBackendId ? 'current' : backend.id,
      onSelect: () => switchBackend(backend),
    })),
    { id: 'app-heading', separator: true, icon: '', label: 'App' },
    {
      id: 'settings',
      icon: 'fa-solid fa-gear',
      label: 'Settings',
      hint: 'open',
      onSelect: () => setSettingsVisible(true),
    },
    { id: 'appearance-heading', separator: true, icon: '', label: 'Appearance' },
    {
      id: 'toggle-theme',
      icon: themeName === 'sunlight' ? 'fa-solid fa-moon' : 'fa-solid fa-sun',
      label: themeName === 'sunlight' ? 'Switch to dark mode' : 'Switch to light mode',
      hint: themeName === 'sunlight' ? 'currently light' : 'currently dark',
      onSelect: () => setThemeName((value) => value === 'sunlight' ? 'dark' : 'sunlight'),
    },
    ...actions,
  ], [activeBackendId, actions, reachableBackends, themeName]);

  return (
    <div className={`cmux-shell theme-${themeName}${navCollapsed ? ' nav-collapsed' : ''}`} style={cssVars({ '--accent': activeWorkspace.color })}>
      <HostBar
        hostName={displayHostName}
        defaultHostName={hostName}
        machineNameColor={machineNameColor}
        stateStatus={stateStatus}
        interactionsEnabled={interactionsEnabled}
        machineIcons={selectedMachineIcons.map(machineIconClass)}
        activePaneInteractionState={activePaneInteractionState}
        activePaneActivityState={activePaneActivityState}
        buttonSettings={hostButtonSettings}
        onToggleInteractions={() => setInteractionsEnabled((value) => !value)}
        onAdjustActivePaneFontSize={(delta) => adjustPaneFontSize(activePane.id, delta)}
        onOpenActivePaneInteraction={() => openPaneInteraction(activePane.id)}
        onOpenActivePaneActivity={() => openPaneActivity(activePane.id)}
        onOpenActivePaneScryerPicker={() => openPaneScryerPicker(activePane.id)}
        onOpenActivePaneQuickInputs={() => openPaneQuickInputs(activePane.id)}
      />
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
        paneFontSize={paneFontSize}
        themeName={themeName}
        terminalFocusToken={terminalFocusToken}
        interactionsEnabled={interactionsEnabled}
        activeBackendId={activeBackendId}
        onActivateWorkspace={activateWorkspace}
        onSetActivePane={setActivePane}
        onOpenCommandInput={openCommandInput}
        onPaneStatus={reportPaneStatus}
        onPaneInteractionState={updatePaneInteractionState}
        onPaneActivityState={updatePaneActivityState}
        onRegisterPaneApi={registerPaneApi}
      />
      <CommandPalette actions={commandActions} />
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
      {settingsVisible ? (
        <SettingsModal
          hostName={machineNameDraft}
          defaultHostName={hostName}
          selectedMachineIcons={selectedMachineIcons}
          onSetMachineIcons={(icons) => setMachineIconsByHost((current) => ({ ...current, [machineCustomizationKey]: icons }))}
          onSetMachineName={(name) => setMachineNamesByHost((current) => ({ ...current, [machineCustomizationKey]: name }))}
          machineNameColor={machineNameColor}
          onSetMachineNameColor={(color) => setMachineNameColorsByHost((current) => ({ ...current, [machineCustomizationKey]: color }))}
          buttonSettings={hostButtonSettings}
          onSetButtonSettings={setHostButtonSettings}
          onClose={() => setSettingsVisible(false)}
        />
      ) : null}
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
