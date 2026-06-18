import { TerminalPane } from './TerminalPane';

export function App() {
  return (
    <div className="cmux-shell">
      <aside className="workspace-sidebar" aria-label="Workspaces">
        <div className="app-title">smux</div>
        <button className="workspace-tab active" title="smux">
          <span className="tab-title">smux</span>
          <span className="tab-meta">main · local shell</span>
          <span className="tab-note">repos/scryer-cmux</span>
        </button>
      </aside>

      <main className="workspace-main">
        <header className="toolbar">
          <div className="toolbar-left">
            <strong>smux</strong>
            <span>repos/scryer-cmux</span>
            <span>main</span>
          </div>
        </header>

        <section className="terminal-stage">
          <article className="pane terminal-pane-card active">
            <div className="pane-titlebar">
              <span>Terminal</span>
              <em>Menlo 12 · local shell</em>
            </div>
            <TerminalPane />
          </article>
        </section>
      </main>
    </div>
  );
}
