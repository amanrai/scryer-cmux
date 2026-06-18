export type PaneKind = 'terminal' | 'browser' | 'notes';
export type AttentionLevel = 'idle' | 'running' | 'needs-input' | 'failed';

export interface PaneModel {
  id: string;
  kind: PaneKind;
  title: string;
  subtitle: string;
  status: AttentionLevel;
  command?: string;
  url?: string;
  output?: string[];
}

export interface WorkspaceModel {
  id: string;
  name: string;
  repo: string;
  branch: string;
  cwd: string;
  ports: number[];
  latest: string;
  unread: number;
  panes: PaneModel[];
}

export const workspaces: WorkspaceModel[] = [
  {
    id: 'surface',
    name: 'Surface build',
    repo: 'scryer-cmux',
    branch: 'main',
    cwd: 'repos/scryer-cmux',
    ports: [43218, 43210],
    latest: 'Terminal renderer decision pending',
    unread: 2,
    panes: [
      {
        id: 'agent-a',
        kind: 'terminal',
        title: 'Agent / frontend',
        subtitle: 'React shell',
        status: 'running',
        command: 'npm run dev',
        output: ['vite v7 ready', 'watching src/App.tsx', 'compiled responsive workspace shell', 'waiting for review signal'],
      },
      {
        id: 'browser-a',
        kind: 'browser',
        title: 'Preview',
        subtitle: 'localhost:43218',
        status: 'idle',
        url: 'http://127.0.0.1:43218',
      },
      {
        id: 'terminal-b',
        kind: 'terminal',
        title: 'Agent / API',
        subtitle: 'contract mock',
        status: 'needs-input',
        command: 'scryer sessions watch',
        output: ['connected to project 24cc...', 'mock event: pane.attention', 'needs decision: ghostty native vs web terminal', 'tap to focus'],
      },
    ],
  },
  {
    id: 'mobile',
    name: 'Mobile pass',
    repo: 'scryer-cmux',
    branch: 'mobile-layout',
    cwd: 'repos/scryer-cmux/src',
    ports: [43218],
    latest: 'Phone pane switcher must be thumb-first',
    unread: 1,
    panes: [
      {
        id: 'phone-notes',
        kind: 'notes',
        title: 'Mobile notes',
        subtitle: 'iPhone viewport',
        status: 'idle',
        output: ['Single active pane on phones', 'Bottom dock exposes panes, notifications, commands', 'Terminal accessory keys: Esc Ctrl Tab ↑ ↓'],
      },
      {
        id: 'phone-term',
        kind: 'terminal',
        title: 'Phone terminal',
        subtitle: 'PTY stream mock',
        status: 'running',
        command: 'pnpm test:mobile',
        output: ['viewport=390x844', 'keyboard-safe-area=true', 'no hover-only controls found'],
      },
    ],
  },
  {
    id: 'alerts',
    name: 'Attention queue',
    repo: 'orchestration-layer',
    branch: 'events',
    cwd: 'repos/orchestration-layer',
    ports: [43212],
    latest: 'Two panes need human input',
    unread: 4,
    panes: [
      {
        id: 'queue',
        kind: 'notes',
        title: 'Notification inbox',
        subtitle: 'all workspaces',
        status: 'needs-input',
        output: ['Agent / API needs terminal renderer decision', 'Backend contract needs session event shape', 'Mobile pass wants shortcut bar labels'],
      },
    ],
  },
];

export const notifications = workspaces.flatMap((workspace) =>
  workspace.panes
    .filter((pane) => pane.status === 'needs-input')
    .map((pane) => ({
      id: `${workspace.id}-${pane.id}`,
      workspaceId: workspace.id,
      paneId: pane.id,
      title: pane.title,
      body: workspace.latest,
      workspace: workspace.name,
    })),
);
