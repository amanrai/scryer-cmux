import type { CSSProperties } from 'react';
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { workspaceColors } from '../constants';
import type { WorkspaceMenuState, WorkspaceModel } from '../types';

type WorkspaceContextMenuProps = {
  menu: WorkspaceMenuState;
  workspaces: WorkspaceModel[];
  onRename: (workspaceId: string) => void;
  onSetColor: (color: string, workspaceId: string) => void;
  onMove: (workspaceId: string, direction: -1 | 1) => void;
  onMoveToEdge: (workspaceId: string, edge: 'top' | 'bottom') => void;
  onDuplicate: (workspaceId: string) => void;
  onClose: (workspaceId: string) => void;
  onCloseOthers: (workspaceId: string) => void;
  onCloseBelow: (workspaceId: string) => void;
  onCloseAbove: (workspaceId: string) => void;
  onDismiss: () => void;
};

function cssVars(vars: Record<string, string>) {
  return vars as CSSProperties;
}

export function WorkspaceContextMenu({
  menu,
  workspaces,
  onRename,
  onSetColor,
  onMove,
  onMoveToEdge,
  onDuplicate,
  onClose,
  onCloseOthers,
  onCloseBelow,
  onCloseAbove,
  onDismiss,
}: WorkspaceContextMenuProps) {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const [pos, setPos] = useState({ x: menu.x, y: menu.y });
  const [colorOpen, setColorOpen] = useState(false);

  const index = workspaces.findIndex((workspace) => workspace.id === menu.workspaceId);
  const workspace = workspaces[index];
  const isFirst = index <= 0;
  const isLast = index === workspaces.length - 1;
  const onlyOne = workspaces.length === 1;

  useLayoutEffect(() => {
    const node = rootRef.current;
    if (!node) return;
    const { width, height } = node.getBoundingClientRect();
    const margin = 8;
    const x = Math.min(menu.x, window.innerWidth - width - margin);
    const y = Math.min(menu.y, window.innerHeight - height - margin);
    setPos({ x: Math.max(margin, x), y: Math.max(margin, y) });
  }, [menu.x, menu.y]);

  useEffect(() => {
    function onPointerDown(event: MouseEvent) {
      if (!rootRef.current?.contains(event.target as Node)) onDismiss();
    }
    function onKey(event: KeyboardEvent) {
      if (event.key === 'Escape') onDismiss();
    }
    window.addEventListener('mousedown', onPointerDown);
    window.addEventListener('keydown', onKey);
    window.addEventListener('resize', onDismiss);
    window.addEventListener('blur', onDismiss);
    return () => {
      window.removeEventListener('mousedown', onPointerDown);
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('resize', onDismiss);
      window.removeEventListener('blur', onDismiss);
    };
  }, [onDismiss]);

  if (!workspace) return null;

  function run(action: () => void) {
    action();
    onDismiss();
  }

  return (
    <div
      ref={rootRef}
      className="context-menu"
      role="menu"
      aria-label={`${workspace.name} actions`}
      style={{ left: pos.x, top: pos.y }}
      onMouseDown={(event) => event.stopPropagation()}
      onContextMenu={(event) => event.preventDefault()}
    >
      <button className="menu-item" type="button" role="menuitem" onClick={() => run(() => onRename(workspace.id))}>
        <i className="menu-icon fa-solid fa-pen" aria-hidden="true" />
        Rename workspace…
      </button>

      <div className="menu-sub" onMouseEnter={() => setColorOpen(true)} onMouseLeave={() => setColorOpen(false)}>
        <button className="menu-item" type="button" role="menuitem" aria-haspopup="true" aria-expanded={colorOpen}>
          <i className="menu-icon fa-solid fa-palette" aria-hidden="true" />
          Workspace color
          <i className="menu-caret fa-solid fa-angle-right" aria-hidden="true" />
        </button>
        {colorOpen ? (
          <div className="context-menu menu-flyout" role="menu" aria-label="Workspace color">
            <div className="menu-swatches">
              {workspaceColors.map((color) => (
                <button
                  key={color.name}
                  className={`color-swatch${workspace.color === color.value ? ' selected' : ''}`}
                  type="button"
                  title={color.name}
                  aria-label={color.name}
                  style={cssVars({ '--chip': color.value })}
                  onClick={() => run(() => onSetColor(color.value, workspace.id))}
                />
              ))}
            </div>
          </div>
        ) : null}
      </div>

      <div className="menu-divider" role="separator" />

      <button className="menu-item" type="button" role="menuitem" disabled={isFirst} onClick={() => run(() => onMove(workspace.id, -1))}>
        <i className="menu-icon fa-solid fa-arrow-up" aria-hidden="true" />
        Move up
      </button>
      <button className="menu-item" type="button" role="menuitem" disabled={isLast} onClick={() => run(() => onMove(workspace.id, 1))}>
        <i className="menu-icon fa-solid fa-arrow-down" aria-hidden="true" />
        Move down
      </button>
      <button className="menu-item" type="button" role="menuitem" disabled={isFirst} onClick={() => run(() => onMoveToEdge(workspace.id, 'top'))}>
        <i className="menu-icon fa-solid fa-angles-up" aria-hidden="true" />
        Move to top
      </button>
      <button className="menu-item" type="button" role="menuitem" disabled={isLast} onClick={() => run(() => onMoveToEdge(workspace.id, 'bottom'))}>
        <i className="menu-icon fa-solid fa-angles-down" aria-hidden="true" />
        Move to bottom
      </button>

      <div className="menu-divider" role="separator" />

      <button className="menu-item" type="button" role="menuitem" onClick={() => run(() => onDuplicate(workspace.id))}>
        <i className="menu-icon fa-solid fa-clone" aria-hidden="true" />
        Duplicate workspace
      </button>

      <div className="menu-divider" role="separator" />

      <button className="menu-item" type="button" role="menuitem" onClick={() => run(() => onClose(workspace.id))}>
        <i className="menu-icon fa-solid fa-xmark" aria-hidden="true" />
        Close workspace
      </button>
      <button className="menu-item" type="button" role="menuitem" disabled={onlyOne} onClick={() => run(() => onCloseOthers(workspace.id))}>
        <i className="menu-icon" aria-hidden="true" />
        Close other workspaces
      </button>
      <button className="menu-item" type="button" role="menuitem" disabled={isLast} onClick={() => run(() => onCloseBelow(workspace.id))}>
        <i className="menu-icon" aria-hidden="true" />
        Close workspaces below
      </button>
      <button className="menu-item" type="button" role="menuitem" disabled={isFirst} onClick={() => run(() => onCloseAbove(workspace.id))}>
        <i className="menu-icon" aria-hidden="true" />
        Close workspaces above
      </button>
    </div>
  );
}
