import { useState } from 'react';

type CommandInputModalProps = {
  paneTitle: string;
  recentLines: string[];
  onSend: (value: string) => void;
  onCancel: () => void;
};

export function CommandInputModal({ paneTitle, recentLines, onSend, onCancel }: CommandInputModalProps) {
  const [draft, setDraft] = useState('');
  const canSend = draft.trim().length > 0;

  return (
    <div className="modal-layer" role="presentation" onMouseDown={onCancel}>
      <form
        className="command-input-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="command-input-title"
        onMouseDown={(event) => event.stopPropagation()}
        onSubmit={(event) => {
          event.preventDefault();
          if (canSend) onSend(draft);
        }}
      >
        <div className="modal-titlebar">
          <div>
            <h2 id="command-input-title">Send to {paneTitle}</h2>
            <p>Enter inserts a newline. Use Send to write the full message to the terminal.</p>
          </div>
          <button type="button" className="modal-close" aria-label="Cancel command input" onClick={onCancel}>
            <i className="fa-solid fa-xmark" aria-hidden="true" />
          </button>
        </div>
        {recentLines.length > 0 ? (
          <div className="command-context" aria-label="Recent terminal output">
            {recentLines.map((line, index) => (
              <div key={`${index}-${line}`} className="command-context-line">{line || ' '}</div>
            ))}
          </div>
        ) : null}
        <label className="field-label" htmlFor="command-input-textarea">Input</label>
        <textarea
          id="command-input-textarea"
          className="command-input-textarea"
          value={draft}
          autoFocus
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          rows={7}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Escape') {
              event.preventDefault();
              onCancel();
            }
          }}
        />
        <div className="modal-actions">
          <button type="button" className="ghost-button" onClick={onCancel}>Cancel</button>
          <button type="submit" className="create-button" disabled={!canSend}>Send</button>
        </div>
      </form>
    </div>
  );
}
