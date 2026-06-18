# scryer-cmux architecture

`scryer-cmux` is a browser-native, mobile-capable cmux-inspired surface for Scryer. It preserves cmux's useful primitives — observable panes, attention state, terminal/browser surfaces, workspace metadata, and scriptable orchestration — without assuming a native macOS shell.

## Current implementation

The first implementation is a React + TypeScript + Vite frontend prototype.

- Dev port: `43218`
- Existing PM API: `43210`
- Future `scryer-cmux` BFF/API target: `43219`

The app currently uses typed mock data in `src/data.ts` so UI work can proceed before the terminal/session backend is finalized.

## Terminal renderer decision

React is the application shell. Ghostty is the visual/behavioral reference, not the default browser runtime.

For browser/mobile delivery, the likely terminal path is:

1. Use an xterm-style browser terminal renderer for PTY streaming.
2. Preserve Ghostty compatibility where it makes sense: colors, themes, font choices, terminal semantics, and keyboard behavior.
3. Do not depend on libghostty in the browser unless research proves it can be shipped safely and performantly across desktop and mobile browsers.

This keeps the product web-native and mobile-capable while still honoring the cmux/Ghostty feel.

## Normalized API direction

The frontend should eventually talk to a thin local BFF under `/api/cmux/*`, instead of directly coupling to tmuxer/orchestrator internals.

### Core models

```ts
type Workspace = {
  id: string;
  title: string;
  cwd: string;
  branch?: string;
  status: 'idle' | 'running' | 'blocked' | 'done' | 'failed';
  paneIds: string[];
  layout: LayoutNode;
  unreadCount: number;
  ports: PortBinding[];
};

type Pane = {
  id: string;
  workspaceId: string;
  kind: 'terminal' | 'browser' | 'log' | 'status';
  title: string;
  status: 'starting' | 'connected' | 'disconnected' | 'exited' | 'blocked';
  attention: 'none' | 'info' | 'needs-input' | 'error';
};

type LayoutNode =
  | { type: 'leaf'; paneId: string }
  | { type: 'split'; direction: 'row' | 'column'; ratio: number; children: LayoutNode[] };
```

### Mock/real endpoints

- `GET /api/cmux/workspaces`
- `POST /api/cmux/workspaces`
- `PATCH /api/cmux/workspaces/:workspaceId`
- `POST /api/cmux/workspaces/:workspaceId/panes`
- `PATCH /api/cmux/panes/:paneId`
- `POST /api/cmux/panes/:paneId/focus`
- `POST /api/cmux/terminals`
- `WS /api/cmux/terminals/:sessionName/attach`
- `POST /api/cmux/terminals/:sessionName/input`
- `POST /api/cmux/terminals/:sessionName/resize`
- `POST /api/cmux/browser-panes`
- `PATCH /api/cmux/browser-panes/:paneId/navigate`
- `GET /api/cmux/notifications`
- `POST /api/cmux/notifications/:id/read`
- `POST /api/cmux/notifications/:id/respond`

## Mobile UX rule

Phones are not miniature desktops. The same workspace/pane data model renders differently:

- Desktop: left sidebar + simultaneous multi-pane observability.
- Tablet: collapsible workspace nav + one/two-pane focus.
- Phone: one active pane, bottom navigation, direct notification inbox, terminal accessory keys.

No Claude Code Teams integration is planned. Agent sessions are generic terminal/process panes.
