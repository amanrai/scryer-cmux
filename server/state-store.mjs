import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { statePath } from './config.mjs';
import { makeId } from './ids.mjs';

const colors = ['#E8B65A', '#5AA6F0', '#6FCB7F', '#4FC9D4', '#B47BE8', '#F0786E', '#8A93A3'];

export function makePane(index) {
  return {
    id: makeId('pane'),
    title: `Terminal ${index}`,
    createdAt: Date.now(),
  };
}

export function makeWorkspace(index) {
  const pane = makePane(1);
  return {
    id: makeId('workspace'),
    name: index === 1 ? 'smux' : `workspace ${index}`,
    color: colors[(index - 1) % colors.length],
    layout: 'row',
    panes: [pane],
    activePaneId: pane.id,
  };
}

export function makeDefaultState() {
  const workspace = makeWorkspace(1);
  return { workspaces: [workspace], activeWorkspaceId: workspace.id };
}

export function sanitizeState(input) {
  if (!input || !Array.isArray(input.workspaces)) return null;
  const workspaces = input.workspaces
    .map((workspace, workspaceIndex) => {
      if (!workspace || !Array.isArray(workspace.panes)) return null;
      const panes = workspace.panes
        .map((pane, paneIndex) => ({
          id: String(pane?.id || makeId('pane')),
          title: String(pane?.title || `Terminal ${paneIndex + 1}`).slice(0, 80),
          createdAt: Number(pane?.createdAt) || Date.now(),
          interactionProducer: pane?.interactionProducer && typeof pane.interactionProducer.from === 'string' ? pane.interactionProducer : undefined,
        }))
        .slice(0, 24);
      if (panes.length === 0) panes.push(makePane(1));
      const activePaneId = panes.some((pane) => pane.id === workspace.activePaneId) ? String(workspace.activePaneId) : panes[0].id;
      return {
        id: String(workspace.id || makeId('workspace')),
        name: String(workspace.name || `workspace ${workspaceIndex + 1}`).slice(0, 80),
        color: /^#[0-9a-fA-F]{6}$/.test(String(workspace.color ?? '')) ? String(workspace.color) : colors[0],
        layout: workspace.layout === 'column' ? 'column' : 'row',
        panes,
        activePaneId,
      };
    })
    .filter(Boolean)
    .slice(0, 24);

  if (workspaces.length === 0) workspaces.push(makeWorkspace(1));
  const activeWorkspaceId = workspaces.some((workspace) => workspace.id === input.activeWorkspaceId) ? String(input.activeWorkspaceId) : workspaces[0].id;
  return { workspaces, activeWorkspaceId };
}

export function loadState() {
  try {
    if (!existsSync(statePath)) return makeDefaultState();
    return sanitizeState(JSON.parse(readFileSync(statePath, 'utf8'))) ?? makeDefaultState();
  } catch {
    return makeDefaultState();
  }
}

export function saveState(state) {
  const tmpPath = `${statePath}.tmp`;
  writeFileSync(tmpPath, JSON.stringify(state, null, 2));
  renameSync(tmpPath, statePath);
}

export function paneIdsFromState(state) {
  return new Set(state.workspaces.flatMap((workspace) => workspace.panes.map((pane) => pane.id)));
}
