import { useEffect, useMemo, useRef, useState } from 'react';

export type CommandAction = {
  id: string;
  label: string;
  icon: string;
  hint?: string;
  depth?: number;
  separator?: boolean;
  onSelect?: () => void;
};

type CommandPaletteProps = {
  actions: CommandAction[];
};

function matches(action: CommandAction, query: string) {
  if (action.separator) return true;
  const haystack = `${action.label} ${action.hint ?? ''}`.toLowerCase();
  return haystack.includes(query.trim().toLowerCase());
}

export function CommandPalette({ actions }: CommandPaletteProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const itemRefs = useRef<Array<HTMLButtonElement | null>>([]);

  const visibleActions = useMemo(() => {
    const filtered = actions.filter((action) => matches(action, query));
    return filtered.filter((action, index) => {
      if (!action.separator) return true;
      const prev = filtered[index - 1];
      const next = filtered[index + 1];
      return Boolean(prev && next && !prev.separator && !next.separator);
    });
  }, [actions, query]);

  const selectableActions = visibleActions.filter((action) => !action.separator && action.onSelect);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setOpen((value) => !value);
      }
    }

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  useEffect(() => {
    if (!open) return;
    setQuery('');
    setSelectedIndex(0);
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, [open]);

  useEffect(() => {
    if (selectedIndex >= selectableActions.length) setSelectedIndex(Math.max(0, selectableActions.length - 1));
  }, [selectableActions.length, selectedIndex]);

  useEffect(() => {
    itemRefs.current[selectedIndex]?.scrollIntoView({ block: 'nearest' });
  }, [selectedIndex]);

  if (!open) return null;

  function close() {
    setOpen(false);
    setQuery('');
    setSelectedIndex(0);
  }

  function select(action?: CommandAction) {
    if (!action?.onSelect) return;
    action.onSelect();
    close();
    window.setTimeout(() => window.dispatchEvent(new CustomEvent('smux:focus-terminal')), 0);
    window.setTimeout(() => window.dispatchEvent(new CustomEvent('smux:focus-terminal')), 150);
  }

  function onInputKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
      return;
    }

    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setSelectedIndex((index) => Math.min(index + 1, Math.max(0, selectableActions.length - 1)));
      return;
    }

    if (event.key === 'ArrowUp') {
      event.preventDefault();
      setSelectedIndex((index) => Math.max(0, index - 1));
      return;
    }

    if (event.key === 'Enter') {
      event.preventDefault();
      select(selectableActions[selectedIndex]);
    }
  }

  let selectableIndex = -1;

  return (
    <div className="palette-layer" role="presentation" onMouseDown={close}>
      <div className="palette" role="dialog" aria-modal="true" aria-label="Command palette" onMouseDown={(event) => event.stopPropagation()}>
        <div className="palette-search">
          <span className="palette-mark">⌘K</span>
          <input
            ref={inputRef}
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setSelectedIndex(0);
            }}
            onKeyDown={onInputKeyDown}
            placeholder="Run a terminal command…"
            aria-label="Search commands"
          />
        </div>

        <div className="palette-list" role="listbox" aria-label="Available commands">
          {visibleActions.length === 0 ? (
            <div className="palette-empty">No commands found</div>
          ) : (
            visibleActions.map((action) => {
              if (action.separator) return <div key={action.id} className="palette-separator" role="separator" />;
              selectableIndex += 1;
              const currentIndex = selectableIndex;
              const selected = currentIndex === selectedIndex;
              return (
                <button
                  key={action.id}
                  ref={(element) => { itemRefs.current[currentIndex] = element; }}
                  className={`palette-item${selected ? ' selected' : ''}`}
                  style={{ paddingLeft: `${12 + (action.depth ?? 0) * 16}px` }}
                  role="option"
                  aria-selected={selected}
                  onMouseEnter={() => setSelectedIndex(currentIndex)}
                  onClick={() => select(action)}
                >
                  <span className="palette-icon">{action.icon}</span>
                  <span className="palette-label">{action.label}</span>
                  {action.hint ? <span className="palette-hint">{action.hint}</span> : null}
                </button>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
