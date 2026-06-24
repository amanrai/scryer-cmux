import Foundation
import MetalKit
import ScryerCore

#if canImport(AppKit)
import AppKit

/// AppKit hosting view for the Metal terminal. Owns the renderer, reports its grid
/// size (cols/rows derived from cell metrics) so the engine/PTY can be resized, and
/// forwards key events for the app to encode via the engine.
///
/// Intentionally imperative (no SwiftUI binding yet) so it can be compiled and
/// exercised before the engine is wired. SwiftUI hosting + app wiring land with the
/// libghostty bridge.
public final class TerminalMetalView: MTKView, MTKViewDelegate {
    public var onGridSizeChange: ((_ cols: Int, _ rows: Int) -> Void)?
    public var onKeyDown: ((NSEvent) -> Void)?
    /// Viewport scroll in rows; negative = up into scrollback history.
    public var onScroll: ((_ deltaRows: Int) -> Void)?
    public var onPaste: ((String) -> Void)?

    private var renderer: MetalTerminalRenderer?
    private var lastReportedCols = 0
    private var lastReportedRows = 0
    private var scrollAccumulator: CGFloat = 0
    private var lastPasteAt: TimeInterval = 0
    private var blinkTimer: Timer?

    public init?(fontSize: CGFloat = 13) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true

        // Rasterize glyphs at device pixels so retina renders crisply and the grid
        // math (drawableSize / cellPx) lines up.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let renderer = MetalTerminalRenderer(device: device, fontSize: fontSize * scale, pixelFormat: colorPixelFormat) else {
            return nil
        }
        self.renderer = renderer
        delegate = self
        startBlinkTimer()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit { blinkTimer?.invalidate() }

    public var cellWidth: Int { renderer?.cellWidth ?? 8 }
    public var cellHeight: Int { renderer?.cellHeight ?? 16 }
    public var horizontalPadding: Int { renderer?.horizontalPadding ?? 6 }

    private func startBlinkTimer() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self, let renderer = self.renderer, renderer.hasVisibleCursor else { return }
            renderer.blinkPhaseOn.toggle()
            self.needsDisplay = true
        }
    }

    /// Rebuilds the renderer/atlas at a new point size, keeping the live session.
    public func updateFontSize(_ fontSize: CGFloat) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let device,
              let newRenderer = MetalTerminalRenderer(device: device, fontSize: fontSize * scale, pixelFormat: colorPixelFormat)
        else { return }
        renderer = newRenderer
        // Force a grid-size report so the engine/PTY reflow to the new cell metrics.
        lastReportedCols = 0
        lastReportedRows = 0
        reportGridSizeIfChanged()
        needsDisplay = true
    }

    /// Push a new snapshot and schedule a redraw.
    public func apply(_ snapshot: TerminalSnapshot) {
        renderer?.update(snapshot)
        needsDisplay = true
    }

    /// cols/rows that currently fit the view at the current cell metrics.
    public func currentGridSize() -> (cols: Int, rows: Int) {
        let scale = window?.backingScaleFactor ?? 2
        let pxWidth = bounds.width * scale
        let pxHeight = bounds.height * scale
        let cols = max(1, (Int(pxWidth) - horizontalPadding * 2) / max(1, cellWidth))
        let rows = max(1, Int(pxHeight) / max(1, cellHeight))
        return (cols, rows)
    }

    private func reportGridSizeIfChanged() {
        // Ignore size changes while detached (reparenting collapses the drawable to a
        // bogus size); only the real, in-window size should resize the engine/PTY.
        guard window != nil, bounds.width >= 1, bounds.height >= 1 else { return }
        let (cols, rows) = currentGridSize()
        guard cols != lastReportedCols || rows != lastReportedRows else { return }
        lastReportedCols = cols
        lastReportedRows = rows
        onGridSizeChange?(cols, rows)
    }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        reportGridSizeIfChanged()
    }

    public func draw(in view: MTKView) {
        renderer?.draw(in: view)
    }

    // MARK: Input

    public override var acceptsFirstResponder: Bool { true }

    public override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    public override func scrollWheel(with event: NSEvent) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let rowHeightPoints = max(1, CGFloat(cellHeight) / scale)
        var rows = 0
        if event.hasPreciseScrollingDeltas {
            scrollAccumulator += event.scrollingDeltaY
            rows = Int((scrollAccumulator / rowHeightPoints).rounded(.towardZero))
            scrollAccumulator -= CGFloat(rows) * rowHeightPoints
        } else {
            rows = Int(event.scrollingDeltaY.rounded()) * 3
        }
        guard rows != 0 else { return }
        renderer?.selection = nil   // selection is viewport-relative; drop it on scroll
        // Positive scrollingDeltaY reveals older lines → scroll viewport up (negative).
        onScroll?(-rows)
    }

    // MARK: Selection & copy

    private var selectionAnchor: MetalTerminalRenderer.GridPoint?
    private var didDragSelection = false

    private func gridPoint(for event: NSEvent) -> MetalTerminalRenderer.GridPoint {
        let p = convert(event.locationInWindow, from: nil)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let cw = max(1, CGFloat(cellWidth) / scale)
        let ch = max(1, CGFloat(cellHeight) / scale)
        // View is not flipped: y increases upward, so row 0 is at the top.
        return .init(col: max(0, Int(p.x / cw)), row: max(0, Int((bounds.height - p.y) / ch)))
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectionAnchor = gridPoint(for: event)
        didDragSelection = false
        renderer?.selection = nil
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let anchor = selectionAnchor else { return }
        didDragSelection = true
        renderer?.selection = .init(anchor: anchor, focus: gridPoint(for: event))
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        if !didDragSelection {
            renderer?.selection = nil   // plain click clears any selection
            needsDisplay = true
        }
        selectionAnchor = nil
    }

    @objc public func copy(_ sender: Any?) {
        guard let text = renderer?.selectedText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // Clipboard paste (⌘V). Routed via performKeyEquivalent so it works without a menu.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            emitPaste()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc public func paste(_ sender: Any?) {
        emitPaste()
    }

    private func emitPaste() {
        // Both the Edit-menu Paste action and performKeyEquivalent can fire for ⌘V;
        // dedupe so a single press pastes once.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPasteAt > 0.05 else { return }
        lastPasteAt = now
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onPaste?(text)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }   // detaching: leave the size as-is
        window?.makeFirstResponder(self)
        // Regained a window (e.g. switched back to this pane): re-assert the size we
        // actually need now, once layout settles.
        lastReportedCols = 0
        lastReportedRows = 0
        reportGridSizeIfChanged()
    }
}
#endif
