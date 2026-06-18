# cmux research notes

Sources checked: cmux.com, manaflow-ai/cmux README, cmux docs/quickstart, YC Launch, and third-party writeups.

## What it is

cmux is an open-source, native macOS terminal for AI coding agents. It wraps Ghostty/libghostty rendering in a Swift/AppKit app and adds agent-oriented workspace primitives: vertical tabs, split panes, browser panes, notifications, and scriptable automation.

## What it looks like

- Native macOS desktop application.
- A vertical sidebar of workspaces/tabs on the left.
- Each workspace can contain split panes, both horizontal and vertical.
- Panes are primarily terminals, with optional in-app browser panes.
- When an agent needs attention, the pane gets a blue notification ring and the related tab lights up.
- Sidebar rows expose useful context: git branch, linked PR status/number, working directory, listening ports, and latest notification text.

## Core features

- **Notification rings**: panes visually highlight when coding agents need attention.
- **Notification panel**: central list of pending notifications; jump to most recent unread.
- **In-app browser**: browser pane can sit alongside terminal panes; includes a scriptable API based on `agent-browser`.
- **Vertical + horizontal tabs/splits**: workspace sidebar plus flexible split layouts.
- **SSH workspaces**: `cmux ssh user@remote` creates a remote workspace; browser panes route through the remote network; image drag/drop can upload via scp.
- **Claude Code Teams**: `cmux claude-teams` starts teammate mode with native splits, sidebar metadata, and notifications.
- **Browser import**: imports cookies/history/sessions from Chrome, Firefox, Arc, and other browsers.
- **Custom commands**: project-specific actions in `cmux.json` launchable from the command palette.
- **Scriptable CLI/socket API**: create workspaces/tabs, split panes, send keystrokes, open URLs, automate browser actions.
- **Native performance**: Swift/AppKit rather than Electron; Ghostty-compatible themes/fonts/colors; GPU-accelerated rendering via libghostty.

## Browser/mobile interpretation for Scryer

The Scryer version should preserve the primitives, not the platform assumptions:

- Replace native macOS shell with responsive browser shell.
- Replace Ghostty rendering dependency with browser terminal primitives, likely xterm-style PTY streaming.
- Keep observable agent panes, but make pane state legible on small screens.
- Treat notifications as both visual badges and a mobile-first inbox.
- Make layouts adaptive:
  - desktop: sidebar + multi-pane splits
  - tablet: collapsible sidebar + one or two primary panes
  - phone: single active pane + fast switcher + status/notification cards
- Preserve scriptability through HTTP/WebSocket APIs rather than only local CLI/socket APIs.

## Product takeaway

cmux is valuable because it makes parallel agent work observable. The browser/mobile Scryer version should focus on visibility, interrupt handling, pane orchestration, and quick recovery from many simultaneous agent sessions.
