import { useMemo } from 'react';
import type { CommandAction } from '../CommandPalette';
import type { PaneModel, WorkspaceModel } from '../types';

type UseCommandActionsArgs = {
  workspaces: WorkspaceModel[];
  activeWorkspace: WorkspaceModel;
  activeWorkspaceId: string;
  activePane: PaneModel;
  activateWorkspace: (workspaceId: string) => void;
  createWorkspace: () => void;
  openRenameWorkspace: () => void;
  duplicateWorkspace: () => void;
  moveWorkspace: (workspaceId: string, direction: -1 | 1) => void;
  closeWorkspace: () => void;
  splitPane: (direction: WorkspaceModel['layout']) => void;
  openRenamePane: (pane: PaneModel) => void;
  closePane: () => void;
};

export function useCommandActions({
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
}: UseCommandActionsArgs) {
  return useMemo<CommandAction[]>(() => {
    const workspaceActions = workspaces.map((workspace) => ({
      id: `switch-workspace-${workspace.id}`,
      icon: workspace.id === activeWorkspaceId ? 'fa-solid fa-circle-dot' : 'fa-regular fa-circle',
      label: workspace.name,
      hint: `${workspace.panes.length} pane${workspace.panes.length === 1 ? '' : 's'}`,
      depth: 1,
      onSelect: () => activateWorkspace(workspace.id),
    }));

    return [
      { id: 'workspace-heading', separator: true, icon: '', label: 'Workspace' },
      { id: 'new-workspace', icon: 'fa-solid fa-plus', label: 'New workspace', hint: 'create', onSelect: createWorkspace },
      { id: 'rename-workspace', icon: 'fa-solid fa-pen', label: 'Rename workspace', hint: activeWorkspace.name, onSelect: openRenameWorkspace },
      { id: 'duplicate-workspace', icon: 'fa-solid fa-clone', label: 'Duplicate workspace', hint: activeWorkspace.name, onSelect: duplicateWorkspace },
      { id: 'move-workspace-up', icon: 'fa-solid fa-arrow-up', label: 'Move workspace up', hint: activeWorkspace.name, onSelect: () => moveWorkspace(activeWorkspaceId, -1) },
      { id: 'move-workspace-down', icon: 'fa-solid fa-arrow-down', label: 'Move workspace down', hint: activeWorkspace.name, onSelect: () => moveWorkspace(activeWorkspaceId, 1) },
      { id: 'close-workspace', icon: 'fa-solid fa-xmark', label: 'Close workspace', hint: activeWorkspace.name, onSelect: closeWorkspace },
      { id: 'switch-workspace-heading', separator: true, icon: '', label: 'Switch workspace' },
      ...workspaceActions,
      { id: 'pane-heading', separator: true, icon: '', label: 'Panes' },
      { id: 'split-right', icon: 'fa-solid fa-grip-lines-vertical', label: 'New terminal right', hint: '⌘T · side by side', onSelect: () => splitPane('row') },
      { id: 'split-down', icon: 'fa-solid fa-grip-lines', label: 'New terminal down', hint: 'stacked', onSelect: () => splitPane('column') },
      { id: 'rename-pane', icon: 'fa-solid fa-pen', label: 'Rename terminal', hint: activePane?.title, onSelect: () => openRenamePane(activePane) },
      ...(activeWorkspace.panes.length > 1 ? [{ id: 'close-pane', icon: 'fa-solid fa-xmark', label: 'Close active pane', hint: activePane?.title, onSelect: closePane }] : []),
    ];
  }, [activePane, activeWorkspace, activeWorkspaceId, activateWorkspace, closePane, closeWorkspace, createWorkspace, duplicateWorkspace, moveWorkspace, openRenamePane, openRenameWorkspace, splitPane, workspaces]);
}
