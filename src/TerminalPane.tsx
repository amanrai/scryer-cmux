import { useEffect, useRef, useState } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { ImageAddon } from '@xterm/addon-image';
import '@xterm/xterm/css/xterm.css';
import { API_BASE, WS_BASE } from './constants';
import { terminalTheme } from './terminal/theme';
import type { SmuxThemeName } from './terminal/theme';
import { shellQuote, uploadFile } from './terminal/upload';
import type { PaneStatus } from './types';

type InteractionChoice = { id: string; label: string; send?: string; custom?: boolean };
type InteractionRequest = {
  id: string;
  from: string;
  kind: string;
  payload: { title?: string; body?: string; choices?: InteractionChoice[] };
};
type SessionUpdate = {
  id: string;
  from: string;
  kind: 'progress' | 'decision' | 'blocked' | 'waiting' | 'done' | 'error' | string;
  title: string;
  body: string;
  level?: 'info' | 'success' | 'warning' | 'error' | string;
  receivedAt?: string;
  createdAt?: string;
};
type PmProject = { id: string; name: string; slug?: string; description_md?: string; relative_repo_path?: string; remote_repo_url?: string };
type PmTask = { id: string; title: string; status?: string; updated_at?: string; description_md?: string; tags?: Array<{ name?: string }> };

export type TerminalPaneApi = {
  sendInput: (data: string) => void;
  getRecentLines: (count?: number) => string[];
  openInteraction: () => void;
  openActivity: () => void;
  openScryerPicker: () => void;
  openQuickInputs: () => void;
};

type TerminalPaneProps = {
  paneId: string;
  active: boolean;
  accentColor: string;
  themeName: SmuxThemeName;
  fontSize: number;
  focusToken: number;
  interactionsEnabled: boolean;
  onStatus?: (paneId: string, status: PaneStatus) => void;
  onRegisterApi?: (paneId: string, api: TerminalPaneApi | null) => void;
  onOpenCommandInput?: () => void;
  onInteractionState?: (paneId: string, state: { hasProducer: boolean; hasPending: boolean }) => void;
  onActivityState?: (paneId: string, state: { count: number; unread: number; latestLevel?: string; latestKind?: string }) => void;
};

type QuickInput = { label: string; description?: string; data: string; icon: string };
type QuickInputGroup = { label: string; items: QuickInput[] };

const quickInputGroups: QuickInputGroup[] = [
  {
    label: 'Terminal',
    items: [
      { label: 'Esc', description: 'Send escape', data: '\x1b', icon: 'fa-door-open' },
      { label: 'Tab', description: 'Autocomplete / indent', data: '\t', icon: 'fa-arrow-right-to-bracket' },
      { label: 'Enter', description: 'Submit current line', data: '\r', icon: 'fa-turn-down' },
      { label: 'Ctrl-C', description: 'Interrupt', data: '\x03', icon: 'fa-ban' },
      { label: 'Ctrl-D', description: 'EOF / exit', data: '\x04', icon: 'fa-right-from-bracket' },
      { label: 'Ctrl-L', description: 'Clear screen', data: '\x0c', icon: 'fa-broom' },
    ],
  },
  {
    label: 'Navigate',
    items: [
      { label: '↑', description: 'Previous history', data: '\x1b[A', icon: 'fa-arrow-up' },
      { label: '↓', description: 'Next history', data: '\x1b[B', icon: 'fa-arrow-down' },
    ],
  },
  {
    label: 'Agent',
    items: [
      { label: 'Force exit', description: 'Double Ctrl-C — stop agent or TUI', data: '\x03\x03', icon: 'fa-circle-stop' },
      { label: '/comms-init', description: 'Re-emit interaction producer', data: '/comms-init\r', icon: 'fa-satellite-dish' },
      { label: '/comms-test', description: 'Create test interaction', data: '/comms-test\r', icon: 'fa-vial' },
      { label: '/comms-test-update', description: 'Create test activity update', data: '/comms-test-update\r', icon: 'fa-timeline' },
      { label: '/comms-status', description: 'Show comms state', data: '/comms-status\r', icon: 'fa-signal' },
      { label: '/save', description: 'Save current Scryer session summary', data: '/save\r', icon: 'fa-floppy-disk' },
      { label: '/reload', description: 'Reload extensions', data: '/reload\r', icon: 'fa-rotate' },
      { label: '/scryer', description: 'Scryer command list', data: '/scryer\r', icon: 'fa-list' },
    ],
  },
  {
    label: 'Git & Project',
    items: [
      { label: 'Commit & push', description: 'Ask agent to commit and push', data: 'commit and push the current changes\r', icon: 'fa-cloud-arrow-up' },
      { label: 'git status', description: 'Run git status', data: 'git status\r', icon: 'fa-code-branch' },
      { label: 'clear', description: 'Clear terminal', data: 'clear\r', icon: 'fa-eraser' },
    ],
  },
];

function QuickInputsModal({ onClose, onSend, onOpenCompose }: { onClose: () => void; onSend: (data: string) => void; onOpenCompose: () => void }) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') { event.stopPropagation(); onClose(); }
    }
    window.addEventListener('keydown', onKeyDown, { capture: true });
    return () => window.removeEventListener('keydown', onKeyDown, { capture: true });
  }, [onClose]);

  return (
    <div className="quick-input-modal" onMouseDown={(event) => event.stopPropagation()}>
      <div className="interaction-pane-header">
        <div className="interaction-eyebrow"><i className="fa-solid fa-bolt" aria-hidden="true" /> Quick Inputs</div>
        <button type="button" className="interaction-close" title="Close (Esc)" onClick={onClose}>
          <i className="fa-solid fa-xmark" aria-hidden="true" />
        </button>
      </div>
      <div className="quick-input-groups">
        {quickInputGroups.map((group) => (
          <section key={group.label} className="quick-input-section">
            <div className="quick-input-section-label">{group.label}</div>
            <div className="quick-input-grid">
              {group.items.map((item) => (
                <button key={item.label} type="button" className="quick-input-item" onClick={() => onSend(item.data)}>
                  <i className={`fa-solid ${item.icon}`} aria-hidden="true" />
                  <span>
                    <strong>{item.label}</strong>
                    {item.description ? <small>{item.description}</small> : null}
                  </span>
                </button>
              ))}
            </div>
          </section>
        ))}
      </div>
      <button type="button" className="quick-input-compose-btn" onClick={onOpenCompose}>
        <i className="fa-solid fa-keyboard" aria-hidden="true" />
        Type…
      </button>
    </div>
  );
}

function compactText(value: unknown, max = 120) {
  return String(value ?? '').replace(/[#*_`>\-\n\r]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}

function taskDescription(task: PmTask) {
  const parts = [String(task.status ?? 'unknown')];
  const tags = (task.tags ?? []).map((tag) => tag.name).filter(Boolean).slice(0, 3).join(', ');
  if (tags) parts.push(tags);
  const desc = compactText(task.description_md, 90);
  if (desc) parts.push(desc);
  return parts.join(' · ');
}

function ScryerPickerModal({ onClose, onSend }: { onClose: () => void; onSend: (data: string) => void }) {
  const [projects, setProjects] = useState<PmProject[]>([]);
  const [tasks, setTasks] = useState<PmTask[]>([]);
  const [selectedProject, setSelectedProject] = useState<PmProject | null>(null);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState('projects');
  const [error, setError] = useState('');

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') { event.stopPropagation(); onClose(); }
    }
    window.addEventListener('keydown', onKeyDown, { capture: true });
    return () => window.removeEventListener('keydown', onKeyDown, { capture: true });
  }, [onClose]);

  useEffect(() => {
    let cancelled = false;
    setLoading('projects');
    fetch(`${API_BASE}/api/pm/projects`)
      .then(async (res) => {
        if (!res.ok) throw new Error(await res.text());
        return res.json();
      })
      .then((data) => {
        if (cancelled) return;
        const list = Array.isArray(data) ? data : [];
        setProjects(list.filter((project) => project?.id && project?.name).sort((a, b) => String(a.name).localeCompare(String(b.name))));
        setLoading('');
      })
      .catch((err) => { if (!cancelled) { setError(err?.message ?? String(err)); setLoading(''); } });
    return () => { cancelled = true; };
  }, []);

  function selectProject(project: PmProject) {
    setSelectedProject(project);
    setQuery('');
    setTasks([]);
    setError('');
    setLoading('tickets');
    onSend(`/pp ${project.id}\r`);
    fetch(`${API_BASE}/api/pm/tasks?project_id=${encodeURIComponent(project.id)}`)
      .then(async (res) => {
        if (!res.ok) throw new Error(await res.text());
        return res.json();
      })
      .then((data) => {
        const list = Array.isArray(data) ? data : [];
        setTasks(list.filter((task) => task?.id && task?.title).sort((a, b) => String(b.updated_at ?? '').localeCompare(String(a.updated_at ?? ''))));
        setLoading('');
      })
      .catch((err) => { setError(err?.message ?? String(err)); setLoading(''); });
  }

  function selectTask(task: PmTask) {
    onSend(`/tp ${task.id}\r`);
    onClose();
  }

  const q = query.trim().toLowerCase();
  const filteredProjects = projects.filter((project) => !q || `${project.name} ${project.slug ?? ''} ${project.remote_repo_url ?? ''} ${project.relative_repo_path ?? ''}`.toLowerCase().includes(q)).slice(0, 80);
  const filteredTasks = tasks.filter((task) => !q || `${task.title} ${task.status ?? ''} ${compactText(task.description_md, 300)}`.toLowerCase().includes(q)).slice(0, 80);

  return (
    <div className="scryer-picker-modal" onMouseDown={(event) => event.stopPropagation()}>
      <div className="interaction-pane-header">
        <div className="interaction-eyebrow"><i className="fa-solid fa-diagram-project" aria-hidden="true" /> Scryer picker</div>
        <button type="button" className="interaction-close" title="Close (Esc)" onClick={onClose}>
          <i className="fa-solid fa-xmark" aria-hidden="true" />
        </button>
      </div>
      <div className="scryer-picker-search-row">
        {selectedProject ? <button type="button" className="ghost-button" onClick={() => { setSelectedProject(null); setQuery(''); }}>Projects</button> : null}
        <input
          className="scryer-picker-search"
          value={query}
          autoFocus
          placeholder={selectedProject ? `Search tickets in ${selectedProject.name}…` : 'Search projects…'}
          onChange={(event) => setQuery(event.target.value)}
        />
      </div>
      {selectedProject ? <div className="scryer-picker-context">Project selected: <strong>{selectedProject.name}</strong>. Choose a ticket, or close to keep project only.</div> : null}
      {error ? <div className="scryer-picker-error">{error}</div> : null}
      {loading ? <div className="activity-empty">Loading {loading}…</div> : null}
      {!selectedProject ? (
        <div className="scryer-picker-list">
          {filteredProjects.map((project) => (
            <button key={project.id} type="button" className="scryer-picker-item" onClick={() => selectProject(project)}>
              <strong>{project.name}</strong>
              <small>{[project.slug, project.relative_repo_path, compactText(project.description_md)].filter(Boolean).join(' · ')}</small>
            </button>
          ))}
        </div>
      ) : (
        <div className="scryer-picker-list">
          {filteredTasks.map((task) => (
            <button key={task.id} type="button" className="scryer-picker-item" onClick={() => selectTask(task)}>
              <strong>{task.title}</strong>
              <small>{taskDescription(task)}</small>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function formatUpdateTime(update: SessionUpdate) {
  const raw = update.receivedAt ?? update.createdAt;
  if (!raw) return '';
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function ActivityPaneModal({ updates, onClose, onDismissUpdate, onDismissAll }: {
  updates: SessionUpdate[];
  onClose: () => void;
  onDismissUpdate: (id: string) => void;
  onDismissAll: () => void;
}) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') { event.stopPropagation(); onClose(); }
    }
    window.addEventListener('keydown', onKeyDown, { capture: true });
    return () => window.removeEventListener('keydown', onKeyDown, { capture: true });
  }, [onClose]);

  return (
    <div className="activity-pane-modal" onMouseDown={(event) => event.stopPropagation()}>
      <div className="interaction-pane-header">
        <div className="interaction-eyebrow"><i className="fa-solid fa-timeline" aria-hidden="true" /> Agent activity</div>
        <div className="activity-header-actions">
          {updates.length ? (
            <button type="button" className="activity-dismiss-all" title="Dismiss all updates from this list" onClick={onDismissAll}>
              Clear all
            </button>
          ) : null}
          <button type="button" className="interaction-close" title="Close (Esc)" onClick={onClose}>
            <i className="fa-solid fa-xmark" aria-hidden="true" />
          </button>
        </div>
      </div>
      {updates.length ? (
        <div className="activity-update-list">
          {[...updates].reverse().map((update) => (
            <article key={update.id} className={`activity-update level-${update.level ?? 'info'} kind-${update.kind}`}>
              <div className="activity-update-meta">
                <span>{formatUpdateTime(update)}</span>
                <span>{update.kind}</span>
                <button type="button" className="activity-update-dismiss" title="Dismiss update" onClick={() => onDismissUpdate(update.id)}>
                  <i className="fa-solid fa-xmark" aria-hidden="true" />
                </button>
              </div>
              <h3>{update.title}</h3>
              <p>{update.body}</p>
            </article>
          ))}
        </div>
      ) : (
        <div className="activity-empty">No updates in this panel yet.</div>
      )}
    </div>
  );
}

function InteractionPaneModal({ request, onClose, onDismiss, onRespond }: {
  request: InteractionRequest;
  onClose: () => void;
  onDismiss: () => void;
  onRespond: (response: Record<string, unknown>) => void;
}) {
  const [custom, setCustom] = useState(false);
  const [draft, setDraft] = useState('');
  const choices = request.payload.choices?.length ? request.payload.choices : [{ id: 'custom', label: 'Type response…', custom: true }];

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') { event.stopPropagation(); onClose(); }
    }
    window.addEventListener('keydown', onKeyDown, { capture: true });
    return () => window.removeEventListener('keydown', onKeyDown, { capture: true });
  }, [onClose]);

  return (
    <div className={`interaction-pane-modal${custom ? ' composing' : ''}`} onMouseDown={(event) => event.stopPropagation()}>
      <div className="interaction-pane-header">
        <div className="interaction-eyebrow"><i className="fa-solid fa-comments" aria-hidden="true" /> Interaction request</div>
        <button type="button" className="interaction-close" title="Close locally" onClick={onClose}>
          <i className="fa-solid fa-xmark" aria-hidden="true" />
        </button>
      </div>
      <div className="interaction-pane-titlebar">
        <h3>{request.payload.title ?? 'Input needed'}</h3>
        {request.payload.body ? <p>{request.payload.body}</p> : null}
      </div>
      <div className="interaction-choice-list" aria-label="Choices">
        {choices.map((choice) => (
          <button
            key={choice.id}
            type="button"
            className={`interaction-choice${choice.custom && custom ? ' selected' : ''}`}
            onClick={() => choice.custom ? setCustom(true) : onRespond({ kind: 'choice', choiceId: choice.id, text: choice.send ?? choice.label })}
          >
            <span>{choice.label}</span>
            <i className={`fa-solid ${choice.custom ? 'fa-keyboard' : 'fa-arrow-right'}`} aria-hidden="true" />
          </button>
        ))}
      </div>
      {custom ? (
        <div className="interaction-composer">
          <label htmlFor={`interaction-custom-${request.id}`}>Custom response</label>
          <textarea
            id={`interaction-custom-${request.id}`}
            className="interaction-custom-input"
            value={draft}
            autoFocus
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            placeholder="Type your response…"
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => {
              if ((event.metaKey || event.ctrlKey) && event.key === 'Enter' && draft.trim()) {
                event.preventDefault();
                onRespond({ kind: 'custom', text: draft.trim() });
              }
            }}
          />
        </div>
      ) : null}
      <div className="interaction-actions">
        <button type="button" className="ghost-button" onClick={onDismiss}>Dismiss</button>
        {custom ? <button type="button" className="create-button" disabled={!draft.trim()} onClick={() => onRespond({ kind: 'custom', text: draft.trim() })}>Send</button> : null}
      </div>
    </div>
  );
}

export function TerminalPane({ paneId, active, accentColor, themeName, fontSize, focusToken, interactionsEnabled, onStatus, onRegisterApi, onOpenCommandInput, onInteractionState, onActivityState }: TerminalPaneProps) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const touchLastYRef = useRef<number | null>(null);
  const touchScrollRemainderRef = useRef(0);
  const touchStartRef = useRef<{ x: number; y: number; moved: boolean } | null>(null);
  const activityVisibleRef = useRef(false);
  const interactionsEnabledRef = useRef(interactionsEnabled);
  const seenUpdateIdsRef = useRef(new Set<string>());
  const dismissedUpdateIdsRef = useRef(new Set<string>());
  const [status, setStatus] = useState<PaneStatus>('connecting');
  const [dropActive, setDropActive] = useState(false);
  const [hasProducer, setHasProducer] = useState(false);
  const [interaction, setInteraction] = useState<InteractionRequest | null>(null);
  const [interactionVisible, setInteractionVisible] = useState(false);
  const [updates, setUpdates] = useState<SessionUpdate[]>([]);
  const [activityVisible, setActivityVisible] = useState(false);
  const [unreadUpdates, setUnreadUpdates] = useState(0);
  const [scryerPickerVisible, setScryerPickerVisible] = useState(false);
  const [quickInputsVisible, setQuickInputsVisible] = useState(false);

  useEffect(() => { activityVisibleRef.current = activityVisible; }, [activityVisible]);
  useEffect(() => { interactionsEnabledRef.current = interactionsEnabled; }, [interactionsEnabled]);

  useEffect(() => {
    if (!interactionsEnabled) setInteractionVisible(false);
  }, [interactionsEnabled]);

  useEffect(() => {
    if (!hostRef.current) return;

    function reportStatus(next: PaneStatus) {
      setStatus(next);
      onStatus?.(paneId, next);
    }

    const term = new Terminal({
      cursorBlink: false,
      fontFamily: '"JetBrainsMono Nerd Font", "JetBrains Mono", ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace',
      fontSize,
      lineHeight: 1.35,
      scrollback: 2000,
      convertEol: true,
      theme: terminalTheme(accentColor, themeName),
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    // Inline images: Sixel + iTerm2 inline-image protocol (kitty not supported).
    term.loadAddon(new ImageAddon({ sixelSupport: true, iipSupport: true }));
    term.open(hostRef.current);
    fit.fit();
    if (active) term.focus();

    const socket = new WebSocket(`${WS_BASE}?paneId=${encodeURIComponent(paneId)}`);
    socketRef.current = socket;
    termRef.current = term;
    fitRef.current = fit;

    socket.addEventListener('open', () => {
      reportStatus('connected');
      socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows, paneId }));
      if (active) {
        window.requestAnimationFrame(() => {
          fit.fit();
          term.focus();
          hostRef.current?.querySelector<HTMLTextAreaElement>('textarea')?.focus();
        });
      }
    });
    socket.addEventListener('message', (event) => {
      const payload = JSON.parse(event.data);
      if (payload.type === 'output') {
        if (payload.replay) {
          term.clear();
          reportStatus('replaying');
          term.write(payload.data, () => reportStatus('connected'));
        } else {
          term.write(payload.data);
        }
      }
      if (payload.type === 'status') {
        if (payload.interactionProducer) setHasProducer(true);
      }
      if (payload.type === 'interaction_producer') setHasProducer(true);
      if (payload.type === 'interaction') {
        const request = payload.request as InteractionRequest | null;
        if (!request?.id) return;
        setInteraction(request);
        setInteractionVisible(interactionsEnabledRef.current);
      }
      if (payload.type === 'interaction_clear') {
        setInteraction(null);
        setInteractionVisible(false);
      }
      if (payload.type === 'session_updates' && Array.isArray(payload.updates)) {
        const incoming = (payload.updates as SessionUpdate[]).filter((update) => update?.id && !dismissedUpdateIdsRef.current.has(update.id));
        const newCount = incoming.filter((update) => !seenUpdateIdsRef.current.has(update.id)).length;
        for (const update of incoming) seenUpdateIdsRef.current.add(update.id);
        setUpdates((current) => {
          const byId = new Map(current.map((update) => [update.id, update]));
          for (const update of incoming) byId.set(update.id, update);
          const next = Array.from(byId.values()).sort((a, b) => String(a.receivedAt ?? a.createdAt ?? '').localeCompare(String(b.receivedAt ?? b.createdAt ?? ''))).slice(-100);
          seenUpdateIdsRef.current = new Set(next.map((update) => update.id));
          return next;
        });
        if (!activityVisibleRef.current && newCount > 0) setUnreadUpdates((count) => count + newCount);
      }
    });

    socket.addEventListener('close', () => {
      reportStatus('closed');
      term.writeln('\r\n\x1b[31m[terminal disconnected]\x1b[0m');
    });
    socket.addEventListener('error', () => {
      term.writeln('\r\n\x1b[31m[terminal backend unavailable]\x1b[0m');
    });

    const dataDisposable = term.onData((data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data, paneId }));
    });

    const resizeObserver = new ResizeObserver(() => {
      fit.fit();
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows, paneId }));
      }
    });
    resizeObserver.observe(hostRef.current);

    return () => {
      dataDisposable.dispose();
      resizeObserver.disconnect();
      socket.close();
      term.dispose();
    };
  }, [paneId]);

  useEffect(() => {
    if (termRef.current) termRef.current.options.theme = terminalTheme(accentColor, themeName);
  }, [accentColor, themeName]);

  useEffect(() => {
    const term = termRef.current;
    if (!term) return;
    term.options.fontSize = fontSize;
    fitRef.current?.fit();
    const socket = socketRef.current;
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows, paneId }));
    }
  }, [fontSize, paneId]);

  useEffect(() => {
    if (!active) return;

    function focusTerminal() {
      fitRef.current?.fit();
      termRef.current?.focus();
      hostRef.current?.querySelector<HTMLTextAreaElement>('textarea')?.focus();
      const socket = socketRef.current;
      const term = termRef.current;
      if (socket?.readyState === WebSocket.OPEN && term) {
        socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows, paneId }));
      }
    }

    const frame = window.requestAnimationFrame(focusTerminal);
    const timer = window.setTimeout(focusTerminal, 120);
    window.addEventListener('smux:focus-terminal', focusTerminal);

    return () => {
      window.cancelAnimationFrame(frame);
      window.clearTimeout(timer);
      window.removeEventListener('smux:focus-terminal', focusTerminal);
    };
  }, [active, paneId, focusToken]);

  function send(data: string, focusAfterSend = true) {
    const socket = socketRef.current;
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data, paneId }));
    if (focusAfterSend) termRef.current?.focus();
  }

  function getRecentLines(count = 12) {
    const term = termRef.current;
    if (!term) return [];
    const buffer = term.buffer.active;
    const end = buffer.baseY + buffer.cursorY;
    const start = Math.max(0, end - count + 1);
    const lines: string[] = [];
    for (let index = start; index <= end; index += 1) {
      lines.push(buffer.getLine(index)?.translateToString(true) ?? '');
    }
    return lines;
  }

  useEffect(() => {
    if (!onRegisterApi) return;
    onRegisterApi(paneId, {
      sendInput: (data) => send(data, false),
      getRecentLines,
      openInteraction: () => { if (interaction) setInteractionVisible(true); },
      openActivity: () => { setActivityVisible(true); setUnreadUpdates(0); },
      openScryerPicker: () => setScryerPickerVisible(true),
      openQuickInputs: () => setQuickInputsVisible(true),
    });
    return () => onRegisterApi(paneId, null);
  }, [paneId, onRegisterApi, interaction, interactionsEnabled]);

  useEffect(() => {
    onInteractionState?.(paneId, { hasProducer, hasPending: !!interaction });
  }, [paneId, hasProducer, interaction, onInteractionState]);

  useEffect(() => {
    const latest = updates[updates.length - 1];
    onActivityState?.(paneId, { count: updates.length, unread: unreadUpdates, latestLevel: latest?.level, latestKind: latest?.kind });
  }, [paneId, updates, unreadUpdates, onActivityState]);

  useEffect(() => {
    if (interactionsEnabledRef.current && active && interaction) setInteractionVisible(true);
  }, [active, interaction]);

  function respondToInteraction(response: Record<string, unknown>) {
    const socket = socketRef.current;
    if (!interaction || socket?.readyState !== WebSocket.OPEN) return;
    socket.send(JSON.stringify({ type: 'interaction_response', request: interaction, response, paneId }));
    setInteractionVisible(false);
  }

  function dismissUpdate(id: string) {
    dismissedUpdateIdsRef.current.add(id);
    setUpdates((current) => current.filter((update) => update.id !== id));
    setUnreadUpdates(0);
  }

  function dismissAllUpdates() {
    setUpdates((current) => {
      for (const update of current) dismissedUpdateIdsRef.current.add(update.id);
      return [];
    });
    setUnreadUpdates(0);
  }

  function onDragOver(event: React.DragEvent) {
    if (!Array.from(event.dataTransfer.types).includes('Files')) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
    setDropActive(true);
  }

  function onDragLeave(event: React.DragEvent) {
    if (event.currentTarget.contains(event.relatedTarget as Node)) return;
    setDropActive(false);
  }

  async function onDrop(event: React.DragEvent) {
    const files = Array.from(event.dataTransfer.files);
    if (files.length === 0) return;
    event.preventDefault();
    setDropActive(false);
    const paths: string[] = [];
    for (const file of files) {
      const savedPath = await uploadFile(file);
      if (savedPath) paths.push(shellQuote(savedPath));
    }
    if (paths.length > 0) send(`${paths.join(' ')} `);
  }

  function onTouchStart(event: React.TouchEvent) {
    if (event.touches.length !== 1) return;
    const touch = event.touches[0];
    touchLastYRef.current = touch.clientY;
    touchStartRef.current = { x: touch.clientX, y: touch.clientY, moved: false };
  }

  function onTouchMove(event: React.TouchEvent) {
    const term = termRef.current;
    const lastY = touchLastYRef.current;
    if (!term || event.touches.length !== 1 || lastY === null) return;
    event.preventDefault();
    const touch = event.touches[0];
    const start = touchStartRef.current;
    if (start && Math.hypot(touch.clientX - start.x, touch.clientY - start.y) > 8) start.moved = true;
    const deltaPx = lastY - touch.clientY;
    touchLastYRef.current = touch.clientY;
    touchScrollRemainderRef.current += deltaPx / Math.max(1, fontSize * 1.35);
    const deltaLines = Math.trunc(touchScrollRemainderRef.current);
    if (deltaLines !== 0) {
      term.scrollLines(deltaLines);
      touchScrollRemainderRef.current -= deltaLines;
    }
  }

  function onTouchEnd(event: React.TouchEvent) {
    const start = touchStartRef.current;
    touchLastYRef.current = null;
    touchScrollRemainderRef.current = 0;
    touchStartRef.current = null;
    if (!start || start.moved) return;
    event.preventDefault();
    setQuickInputsVisible(true);
  }

  return (
    <div
      className={`terminal-wrap${dropActive ? ' drop-active' : ''}`}
      data-status={status}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
    >
      <div
        ref={hostRef}
        className="xterm-host"
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        onTouchCancel={onTouchEnd}
      />
      {dropActive ? <div className="drop-overlay" aria-hidden="true">Drop to add file path</div> : null}
      {interaction && interactionVisible ? (
        <>
          <div className="modal-touch-guard" aria-hidden="true" />
          <InteractionPaneModal
            request={interaction}
            onClose={() => setInteractionVisible(false)}
            onDismiss={() => respondToInteraction({ kind: 'dismiss' })}
            onRespond={respondToInteraction}
          />
        </>
      ) : null}
      {activityVisible ? (
        <>
          <div className="modal-touch-guard" aria-hidden="true" />
          <ActivityPaneModal updates={updates} onClose={() => setActivityVisible(false)} onDismissUpdate={dismissUpdate} onDismissAll={dismissAllUpdates} />
        </>
      ) : null}
      {scryerPickerVisible ? (
        <>
          <div className="modal-touch-guard" aria-hidden="true" />
          <ScryerPickerModal onClose={() => setScryerPickerVisible(false)} onSend={(data) => send(data, false)} />
        </>
      ) : null}
      {quickInputsVisible ? (
        <>
          <div className="modal-touch-guard" aria-hidden="true" />
          <QuickInputsModal
            onClose={() => setQuickInputsVisible(false)}
            onSend={(data) => { send(data, false); setQuickInputsVisible(false); }}
            onOpenCompose={() => { setQuickInputsVisible(false); onOpenCommandInput?.(); }}
          />
        </>
      ) : null}
      <div className="terminal-accessory" aria-label="Terminal shortcuts">
        <button onClick={() => send('\x1b')}>Esc</button>
        <button onClick={() => send('\t')}>Tab</button>
        <button onClick={() => send('\x03')}>Ctrl-C</button>
        <button onClick={() => send('\r')}>Enter</button>
        <button onClick={() => send('[A')}>↑</button>
        <button onClick={() => send('[B')}>↓</button>
      </div>
    </div>
  );
}
