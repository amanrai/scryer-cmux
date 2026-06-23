import type { CSSProperties } from 'react';
import { workspaceColors } from '../constants';
import type { ColorPickerState, WorkspaceModel } from '../types';

type ColorPickerProps = {
  picker: ColorPickerState;
  workspaces: WorkspaceModel[];
  onSetColor: (color: string, workspaceId: string) => void;
  onClose: () => void;
};

function cssVars(vars: Record<string, string>) {
  return vars as CSSProperties;
}

export function ColorPicker({ picker, workspaces, onSetColor, onClose }: ColorPickerProps) {
  const workspace = workspaces.find((item) => item.id === picker.workspaceId);

  return (
    <div className="picker-layer" role="presentation" onMouseDown={onClose}>
      <div
        className="color-picker"
        role="dialog"
        aria-label="Workspace color"
        style={{ left: picker.x, top: picker.y }}
        onMouseDown={(event) => event.stopPropagation()}
      >
        {workspaceColors.map((color) => {
          const selected = workspace?.color === color.value;
          return (
            <button
              key={color.name}
              className={`color-swatch${selected ? ' selected' : ''}`}
              type="button"
              title={color.name}
              aria-label={color.name}
              aria-pressed={selected}
              style={cssVars({ '--chip': color.value })}
              onClick={() => {
                onSetColor(color.value, picker.workspaceId);
                onClose();
              }}
            />
          );
        })}
      </div>
    </div>
  );
}
