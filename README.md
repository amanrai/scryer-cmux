# scryer-cmux

Browser-native, mobile-capable cmux-inspired workspace for Scryer.

The goal is not to clone cmux's macOS app shell. The goal is to bring its useful primitives into a web surface that works from desktop browsers, tablets, and phones:

- observable multi-agent workspaces
- terminal/session panes
- browser/dev-server panes
- notification state that says which agent needs attention and why
- split/focused layouts that adapt to small screens
- command/API primitives for orchestration

## Baseline: what cmux does

cmux is a native macOS terminal built on Ghostty for running AI coding agents in parallel. Its visible product shape is:

- left vertical workspace/tab sidebar
- split terminal panes inside each workspace
- built-in browser panes next to terminals
- blue notification rings around panes that need attention
- sidebar metadata: git branch, PR info, working directory, listening ports, latest notification text
- scriptable CLI/socket API for workspace, pane, notification, and browser automation

See [`docs/cmux-research.md`](docs/cmux-research.md) for the initial feature inventory.

## Scryer direction

For Scryer, this becomes a responsive web app:

- desktop: cmux-like multi-pane grid with sidebar and browser/terminal splits
- tablet: two-pane/focus workflow with collapsible sidebar
- phone: single active pane, quick-switcher, notification inbox, and task/agent status cards

## Running locally

```bash
npm install
npm run dev
```

The Vite dev server defaults to `http://127.0.0.1:43218`.

## Current status

The repo now contains the first React prototype:

- cmux-like desktop workspace sidebar and pane grid
- browser/terminal/notes pane mocks
- attention rings and notification inbox
- mobile single-pane mode with bottom navigation and terminal shortcut keys
- command palette shell

See [`docs/architecture.md`](docs/architecture.md) for the terminal renderer decision and future `/api/cmux/*` contract.
