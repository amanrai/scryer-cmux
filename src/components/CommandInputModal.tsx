import { useState } from 'react';

type CommandInputModalProps = {
  paneTitle: string;
  recentLines: string[];
  onSend: (value: string) => void;
  onCancel: () => void;
};

export function CommandInputModal({ paneTitle, recentLines, onSend, onCancel }: CommandInputModalProps) {
  const [draft, setDraft] = useState('');
  const [contextExpanded, setContextExpanded] = useState(false);
  const canSend = draft.trim().length > 0;
  const visibleLines = contextExpanded ? recentLines : recentLines.slice(-3);

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
          <section className={`command-context-shell${contextExpanded ? ' expanded' : ''}`} aria-label="Recent terminal output">
            <button
              type="button"
              className="command-context-toggle"
              aria-expanded={contextExpanded}
              onClick={() => setContextExpanded((value) => !value)}
            >
              <span>Terminal state</span>
              <span className="command-context-toggle-hint">
                <i className={`fa-solid ${contextExpanded ? 'fa-chevron-up' : 'fa-chevron-down'}`} aria-hidden="true" />
                {contextExpanded ? 'Collapse' : 'Expand'}
              </span>
            </button>
            <div className="command-context">
              {visibleLines.map((line, index) => (
                <div key={`${index}-${line}`} className="command-context-line">{line || ' '}</div>
              ))}
            </div>
          </section>
        ) : null}
        <label className="field-label" htmlFor="command-input-textarea">Input</label>
        <textarea
          id="command-input-textarea"
          className="command-input-textarea"
          value={draft}
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
