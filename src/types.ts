export type PaneStatus = 'connecting' | 'connected' | 'closed';

export type PaneModel = {
  id: string;
  title: string;
  createdAt: number;
};

export type WorkspaceModel = {
  id: string;
  name: string;
  color: string;
  layout: 'row' | 'column';
  panes: PaneModel[];
  activePaneId: string;
};

export type AppState = {
  workspaces: WorkspaceModel[];
  activeWorkspaceId: string;
  hostName?: string;
};

export type RenameTarget = {
  kind: 'workspace' | 'pane';
  id: string;
};

export type ColorPickerState = {
  workspaceId: string;
  x: number;
  y: number;
};

export type WorkspaceMenuState = {
  workspaceId: string;
  x: number;
  y: number;
};
