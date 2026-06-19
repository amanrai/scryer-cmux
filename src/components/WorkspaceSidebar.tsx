import type { CSSProperties, KeyboardEvent, MouseEvent } from 'react';
import type { ColorPickerState, WorkspaceModel } from '../types';

type WorkspaceSidebarProps = {
  workspaces: WorkspaceModel[];
  activeWorkspaceId: string;
  draggedWorkspaceId: string | null;
  navCollapsed: boolean;
  onToggleCollapsed: () => void;
  onCreateWorkspace: () => void;
  onActivateWorkspace: (workspaceId: string) => void;
  onCloseWorkspace: (workspaceId: string) => void;
  onRenameWorkspace: (workspaceId: string) => void;
  onReorderWorkspace: (sourceId: string, targetId: string) => void;
  onSetDraggedWorkspaceId: (workspaceId: string | null) => void;
  onSetColorPicker: (picker: ColorPickerState | null | ((current: ColorPickerState | null) => ColorPickerState | null)) => void;
};

function cssVars(vars: Record<string, string>) {
  return vars as CSSProperties;
}

export function WorkspaceSidebar({
  workspaces,
  activeWorkspaceId,
  draggedWorkspaceId,
  navCollapsed,
  onToggleCollapsed,
  onCreateWorkspace,
  onActivateWorkspace,
  onCloseWorkspace,
  onRenameWorkspace,
  onReorderWorkspace,
  onSetDraggedWorkspaceId,
  onSetColorPicker,
}: WorkspaceSidebarProps) {
  function activateFromKeyboard(event: KeyboardEvent, workspaceId: string) {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    event.preventDefault();
    onActivateWorkspace(workspaceId);
  }

  function handleWorkspaceClick(event: MouseEvent<HTMLDivElement>, workspace: WorkspaceModel) {
    if (workspace.id !== activeWorkspaceId) {
      onSetColorPicker(null);
      onActivateWorkspace(workspace.id);
      return;
    }

    const rect = event.currentTarget.getBoundingClientRect();
    onSetColorPicker((current) =>
      current?.workspaceId === workspace.id ? null : { workspaceId: workspace.id, x: rect.right + 8, y: rect.top },
    );
  }

  return (
    <aside className="workspace-sidebar" aria-label="Workspaces">
      <div className="sidebar-head">
        <span className="sidebar-title eyebrow">Workspaces</span>
        <button
          className="nav-toggle"
          type="button"
          onClick={onToggleCollapsed}
          title={navCollapsed ? 'Expand workspace nav' : 'Collapse workspace nav'}
          aria-label={navCollapsed ? 'Expand workspace nav' : 'Collapse workspace nav'}
          aria-expanded={!navCollapsed}
        >
          <i className={`fa-solid ${navCollapsed ? 'fa-angle-right' : 'fa-angle-left'}`} aria-hidden="true" />
        </button>
      </div>

      <div className="workspace-list">
        {workspaces.map((workspace) => (
          <div
            key={workspace.id}
            className={`workspace-tab${workspace.id === activeWorkspaceId ? ' active' : ''}${workspace.id === draggedWorkspaceId ? ' dragging' : ''}`}
            style={cssVars({ '--chip': workspace.color })}
            title={workspace.name}
            role="button"
            tabIndex={0}
            draggable
            onDragStart={(event) => {
              onSetDraggedWorkspaceId(workspace.id);
              event.dataTransfer.effectAllowed = 'move';
              event.dataTransfer.setData('text/plain', workspace.id);
            }}
            onDragOver={(event) => {
              event.preventDefault();
              event.dataTransfer.dropEffect = 'move';
            }}
            onDrop={(event) => {
              event.preventDefault();
              const sourceId = event.dataTransfer.getData('text/plain') || draggedWorkspaceId;
              if (sourceId) onReorderWorkspace(sourceId, workspace.id);
              onSetDraggedWorkspaceId(null);
            }}
            onDragEnd={() => onSetDraggedWorkspaceId(null)}
            onDoubleClick={() => {
              onSetColorPicker(null);
              onRenameWorkspace(workspace.id);
            }}
            onClick={(event) => handleWorkspaceClick(event, workspace)}
            onKeyDown={(event) => activateFromKeyboard(event, workspace.id)}
          >
            <span className="tab-glyph" aria-hidden="true">{workspace.name.charAt(0).toUpperCase()}</span>
            <div className="tab-main">
              <span className="tab-title">{workspace.name}</span>
              <span className="tab-meta">{workspace.panes.length} pane{workspace.panes.length === 1 ? '' : 's'}</span>
            </div>
            <button
              className="workspace-close"
              type="button"
              title={`Close ${workspace.name}`}
              aria-label={`Close ${workspace.name}`}
              onClick={(event) => {
                event.stopPropagation();
                onCloseWorkspace(workspace.id);
              }}
            >
              <i className="fa-solid fa-xmark" aria-hidden="true" />
            </button>
          </div>
        ))}
      </div>

      <div className="sidebar-foot">
        <button className="new-workspace-button" type="button" onClick={onCreateWorkspace} title="New workspace">
          <i className="plus fa-solid fa-plus" aria-hidden="true" />
          <span className="label">New workspace</span>
        </button>
      </div>
    </aside>
  );
}
