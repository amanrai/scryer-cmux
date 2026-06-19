import type { RenameTarget } from '../types';

type RenameModalProps = {
  target: RenameTarget;
  draft: string;
  onDraftChange: (value: string) => void;
  onSubmit: () => void;
  onCancel: () => void;
};

export function RenameModal({ target, draft, onDraftChange, onSubmit, onCancel }: RenameModalProps) {
  const isWorkspace = target.kind === 'workspace';

  return (
    <div className="modal-layer" role="presentation" onMouseDown={onCancel}>
      <form
        className="rename-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="rename-title"
        onMouseDown={(event) => event.stopPropagation()}
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit();
        }}
      >
        <div className="modal-titlebar">
          <div>
            <h2 id="rename-title">{isWorkspace ? 'Rename workspace' : 'Rename terminal'}</h2>
            <p>{isWorkspace ? 'Give this terminal workspace a short, memorable name.' : 'Give this terminal a short, memorable name.'}</p>
          </div>
          <button type="button" className="modal-close" aria-label="Cancel rename" onClick={onCancel}>
            <i className="fa-solid fa-xmark" aria-hidden="true" />
          </button>
        </div>
        <label className="field-label" htmlFor="rename-name-input">{isWorkspace ? 'Workspace name' : 'Terminal name'}</label>
        <input
          id="rename-name-input"
          className="rename-input"
          value={draft}
          autoFocus
          onChange={(event) => onDraftChange(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Escape') {
              event.preventDefault();
              onCancel();
            }
          }}
        />
        <div className="modal-actions">
          <button type="button" className="ghost-button" onClick={onCancel}>Cancel</button>
          <button type="submit" className="create-button" disabled={!draft.trim()}>Rename</button>
        </div>
      </form>
    </div>
  );
}
