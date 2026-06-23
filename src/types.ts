export type PaneStatus = 'connecting' | 'connected' | 'replaying' | 'closed';

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

export type BackendMachine = {
  id: string;
  label: string;
  kind: string;
  baseUrl?: string;
  transport?: string;
  capabilities?: string[];
  status?: 'online' | 'stale' | 'offline' | 'unknown';
  lastSeenAt?: string;
  registeredAt?: string;
  source?: string;
  hostInfo?: Record<string, unknown>;
};

export type PtyGatewayConfig = {
  gatewayUrl: string;
  machineId: string;
  machineName: string;
  publicUrl: string;
  heartbeatEnabled: boolean;
  heartbeatMs: number;
};

export type PtyConfigPayload = {
  config: PtyGatewayConfig;
  status?: {
    registered?: boolean;
    lastSuccessAt?: string;
    lastAttemptAt?: string;
    lastError?: string;
    gatewayResponse?: BackendMachine;
  };
};
