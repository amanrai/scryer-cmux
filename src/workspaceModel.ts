import { workspaceColors } from './constants';
import type { PaneModel, WorkspaceModel } from './types';

export function makeId(prefix: string) {
  const randomUUID = globalThis.crypto?.randomUUID?.bind(globalThis.crypto);
  if (randomUUID) return `${prefix}-${randomUUID()}`;
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export function makePane(index: number): PaneModel {
  return {
    id: makeId('pane'),
    title: `Terminal ${index}`,
    createdAt: Date.now(),
  };
}

export function makeWorkspace(index: number): WorkspaceModel {
  const pane = makePane(1);
  return {
    id: makeId('workspace'),
    name: index === 1 ? 'smux' : `workspace ${index}`,
    color: workspaceColors[(index - 1) % workspaceColors.length].value,
    layout: 'row',
    panes: [pane],
    activePaneId: pane.id,
  };
}
