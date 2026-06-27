import Foundation
import MetalKit
import ScryerCore

/// Platform-agnostic terminal render state: owns the renderer, grid math, blink, and
/// the selection model. The AppKit/UIKit hosting views below own one of these and
/// forward input/lifecycle to it, so the heavy logic lives in one place.
final class TerminalRenderSurface {
    private(set) var renderer: MetalTerminalRenderer?
    let device: MTLDevice
    let pixelFormat: MTLPixelFormat
    var lastReportedCols = 0
    var lastReportedRows = 0
    var scrollAccumulator: CGFloat = 0
    private var selectionAnchor: MetalTerminalRenderer.GridPoint?
    private(set) var didDragSelection = false

    init?(device: MTLDevice, fontSize: CGFloat, scale: CGFloat, pixelFormat: MTLPixelFormat) {
        guard let renderer = MetalTerminalRenderer(device: device, fontSize: fontSize * scale, pixelFormat: pixelFormat) else { return nil }
        self.device = device
        self.pixelFormat = pixelFormat
        self.renderer = renderer
    }

    var cellWidth: Int { renderer?.cellWidth ?? 8 }
    var cellHeight: Int { renderer?.cellHeight ?? 16 }
    var horizontalPadding: Int { renderer?.horizontalPadding ?? 6 }

    func apply(_ snapshot: TerminalSnapshot) { renderer?.update(snapshot) }
    func draw(in view: MTKView) { renderer?.draw(in: view) }

    /// Toggle the cursor blink phase; returns true if a redraw is warranted.
    func toggleBlink() -> Bool {
        guard let renderer, renderer.hasVisibleCursor else { return false }
        renderer.blinkPhaseOn.toggle()
        return true
    }

    /// Rebuild the renderer/atlas at a new point size, keeping the live session.
    @discardableResult
    func rebuild(fontSize: CGFloat, scale: CGFloat) -> Bool {
        guard let renderer = MetalTerminalRenderer(device: device, fontSize: fontSize * scale, pixelFormat: pixelFormat) else { return false }
        self.renderer = renderer
        lastReportedCols = 0
        lastReportedRows = 0
        return true
    }

    func gridSize(widthPoints: CGFloat, heightPoints: CGFloat, scale: CGFloat) -> (cols: Int, rows: Int) {
        let pxWidth = widthPoints * scale
        let pxHeight = heightPoints * scale
        let cols = max(1, (Int(pxWidth) - horizontalPadding * 2) / max(1, cellWidth))
        let rows = max(1, Int(pxHeight) / max(1, cellHeight))
        return (cols, rows)
    }

    /// `topYPoints` is measured from the top of the view (callers flip for AppKit).
    func gridPoint(xPoints: CGFloat, topYPoints: CGFloat, scale: CGFloat) -> MetalTerminalRenderer.GridPoint {
        let cw = max(1, CGFloat(cellWidth) / scale)
        let ch = max(1, CGFloat(cellHeight) / scale)
        return .init(col: max(0, Int(xPoints / cw)), row: max(0, Int(topYPoints / ch)))
    }

    var selection: MetalTerminalRenderer.Selection? {
        get { renderer?.selection }
        set { renderer?.selection = newValue }
    }
    func selectedText() -> String? { renderer?.selectedText() }

    func beginSelection(at point: MetalTerminalRenderer.GridPoint) {
        selectionAnchor = point
        didDragSelection = false
        renderer?.selection = nil
    }
    func dragSelection(to point: MetalTerminalRenderer.GridPoint) {
        guard let anchor = selectionAnchor else { return }
        didDragSelection = true
        renderer?.selection = .init(anchor: anchor, focus: point)
    }
    func endSelection() { selectionAnchor = nil }

    /// Fold a precise scroll delta (points) into whole rows of viewport movement.
    func accumulatePreciseScroll(deltaPoints: CGFloat, scale: CGFloat) -> Int {
        let rowHeightPoints = max(1, CGFloat(cellHeight) / scale)
        scrollAccumulator += deltaPoints
        let rows = Int((scrollAccumulator / rowHeightPoints).rounded(.towardZero))
        scrollAccumulator -= CGFloat(rows) * rowHeightPoints
        return rows
    }
}

#if os(macOS)
import AppKit

/// AppKit hosting view for the Metal terminal. Forwards key/scroll/mouse events and
/// reports grid size so the engine/PTY can resize.
public final class TerminalMetalView: MTKView, MTKViewDelegate {
    public var onGridSizeChange: ((_ cols: Int, _ rows: Int) -> Void)?
    public var onKeyDown: ((NSEvent) -> Void)?
    /// Viewport scroll in rows; negative = up into scrollback history.
    public var onScroll: ((_ deltaRows: Int) -> Void)?
    public var onPaste: ((String) -> Void)?

    private var surface: TerminalRenderSurface!
    private var lastPasteAt: TimeInterval = 0
    private var blinkTimer: Timer?
    private var pendingGridReport: DispatchWorkItem?

    public init?(fontSize: CGFloat = 13) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let surface = TerminalRenderSurface(device: device, fontSize: fontSize, scale: scale, pixelFormat: colorPixelFormat) else { return nil }
        self.surface = surface
        delegate = self
        startBlinkTimer()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        blinkTimer?.invalidate()
        pendingGridReport?.cancel()
    }

    public var cellWidth: Int { surface.cellWidth }
    public var cellHeight: Int { surface.cellHeight }

    private var currentScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private func startBlinkTimer() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self, self.surface.toggleBlink() else { return }
            self.needsDisplay = true
        }
    }

    public func updateFontSize(_ fontSize: CGFloat) {
        guard surface.rebuild(fontSize: fontSize, scale: currentScale) else { return }
        reportGridSizeIfChanged()
        needsDisplay = true
    }

    public func apply(_ snapshot: TerminalSnapshot) {
        surface.apply(snapshot)
        needsDisplay = true
    }

    public func currentGridSize() -> (cols: Int, rows: Int) {
        surface.gridSize(widthPoints: bounds.width, heightPoints: bounds.height, scale: currentScale)
    }

    private func reportGridSizeIfChanged() {
        guard surface != nil, window != nil, bounds.width >= 1, bounds.height >= 1 else { return }
        let (cols, rows) = currentGridSize()
        guard cols != surface.lastReportedCols || rows != surface.lastReportedRows else { return }
        surface.lastReportedCols = cols
        surface.lastReportedRows = rows
        onGridSizeChange?(cols, rows)
    }

    private func scheduleGridSizeReport(after delay: TimeInterval = 0.09) {
        pendingGridReport?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reportGridSizeIfChanged() }
        pendingGridReport = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Coalesce live window-resize/layout churn. TUIs repaint on SIGWINCH, so sending
        // every transient size makes the terminal flash/repaint repeatedly while dragging.
        scheduleGridSizeReport()
    }
    public func draw(in view: MTKView) { surface.draw(in: view) }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleGridSizeReport()
    }

    public override func layout() {
        super.layout()
        scheduleGridSizeReport()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        surface.lastReportedCols = 0
        surface.lastReportedRows = 0
        scheduleGridSizeReport(after: 0)
        needsDisplay = true
    }

    public override var acceptsFirstResponder: Bool { true }
    public override func keyDown(with event: NSEvent) { onKeyDown?(event) }

    public override func scrollWheel(with event: NSEvent) {
        var rows = 0
        if event.hasPreciseScrollingDeltas {
            rows = surface.accumulatePreciseScroll(deltaPoints: event.scrollingDeltaY, scale: currentScale)
        } else {
            rows = Int(event.scrollingDeltaY.rounded()) * 3
        }
        guard rows != 0 else { return }
        surface.selection = nil
        onScroll?(-rows)   // positive deltaY reveals older lines → viewport up
    }

    private func gridPoint(for event: NSEvent) -> MetalTerminalRenderer.GridPoint {
        let p = convert(event.locationInWindow, from: nil)
        // View is not flipped (y up): flip to top-origin for the surface.
        return surface.gridPoint(xPoints: p.x, topYPoints: bounds.height - p.y, scale: currentScale)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        surface.beginSelection(at: gridPoint(for: event))
        needsDisplay = true
    }
    public override func mouseDragged(with event: NSEvent) {
        surface.dragSelection(to: gridPoint(for: event))
        needsDisplay = true
    }
    public override func mouseUp(with event: NSEvent) {
        if !surface.didDragSelection { surface.selection = nil; needsDisplay = true }
        surface.endSelection()
    }

    @objc public func copy(_ sender: Any?) {
        guard let text = surface.selectedText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            emitPaste()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc public func paste(_ sender: Any?) { emitPaste() }

    private func emitPaste() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPasteAt > 0.05 else { return }
        lastPasteAt = now
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onPaste?(text)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        window?.makeFirstResponder(self)
        surface.lastReportedCols = 0
        surface.lastReportedRows = 0
        reportGridSizeIfChanged()
    }
}

#elseif os(iOS)
import UIKit

/// UIKit hosting view for the Metal terminal. Typed text + the software keyboard come
/// via `UIKeyInput`; hardware-keyboard special keys via `pressesBegan`; scrollback via
/// a pan gesture. Reports grid size so the engine/PTY can resize.
public final class TerminalMetalView: MTKView, MTKViewDelegate, UIKeyInput {
    public var onGridSizeChange: ((_ cols: Int, _ rows: Int) -> Void)?
    /// Typed text + modifiers (modifiers usually empty; control set for ⌃-combos).
    public var onText: ((String, KeyModifiers) -> Void)?
    public var onSpecialKey: ((TerminalKey, KeyModifiers) -> Void)?
    public var onScroll: ((_ deltaRows: Int) -> Void)?
    public var onPaste: ((String) -> Void)?

    private var surface: TerminalRenderSurface!
    private var blinkTimer: Timer?
    private var lastPanY: CGFloat = 0
    private var momentumLink: CADisplayLink?
    private var momentumVelocity: CGFloat = 0   // points/sec, decays

    public init?(fontSize: CGFloat = 13) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        isMultipleTouchEnabled = true

        let scale = UIScreen.main.scale
        guard let surface = TerminalRenderSurface(device: device, fontSize: fontSize, scale: scale, pixelFormat: colorPixelFormat) else { return nil }
        self.surface = surface
        delegate = self

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        startBlinkTimer()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit { blinkTimer?.invalidate(); momentumLink?.invalidate() }

    public var cellWidth: Int { surface.cellWidth }
    public var cellHeight: Int { surface.cellHeight }

    private var currentScale: CGFloat {
        window?.windowScene?.screen.scale ?? (traitCollection.displayScale > 0 ? traitCollection.displayScale : UIScreen.main.scale)
    }

    private func startBlinkTimer() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self, self.surface.toggleBlink() else { return }
            self.setNeedsDisplay()
        }
    }

    public func updateFontSize(_ fontSize: CGFloat) {
        guard surface.rebuild(fontSize: fontSize, scale: currentScale) else { return }
        reportGridSizeIfChanged()
        setNeedsDisplay()
    }

    public func apply(_ snapshot: TerminalSnapshot) {
        surface.apply(snapshot)
        setNeedsDisplay()
    }

    public func currentGridSize() -> (cols: Int, rows: Int) {
        surface.gridSize(widthPoints: bounds.width, heightPoints: bounds.height, scale: currentScale)
    }

    private func reportGridSizeIfChanged() {
        guard window != nil, bounds.width >= 1, bounds.height >= 1 else { return }
        let (cols, rows) = currentGridSize()
        guard cols != surface.lastReportedCols || rows != surface.lastReportedRows else { return }
        surface.lastReportedCols = cols
        surface.lastReportedRows = rows
        onGridSizeChange?(cols, rows)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { reportGridSizeIfChanged() }
    public func draw(in view: MTKView) { surface.draw(in: view) }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        surface.lastReportedCols = 0
        surface.lastReportedRows = 0
        reportGridSizeIfChanged()
        becomeFirstResponder()
    }

    // MARK: Scrolling

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            stopMomentum()
            lastPanY = g.location(in: self).y
        case .changed:
            let y = g.location(in: self).y
            let delta = y - lastPanY
            lastPanY = y
            scrollBy(deltaPoints: delta)
        case .ended:
            momentumVelocity = g.velocity(in: self).y
            startMomentum()
        case .cancelled, .failed:
            stopMomentum()
        default:
            break
        }
    }

    private func scrollBy(deltaPoints: CGFloat) {
        let rows = surface.accumulatePreciseScroll(deltaPoints: deltaPoints, scale: currentScale)
        guard rows != 0 else { return }
        surface.selection = nil
        onScroll?(-rows)   // dragging down reveals older lines → viewport up
    }

    // Inertial scrolling: decay the fling velocity over a display link.
    private func startMomentum() {
        guard abs(momentumVelocity) > 60 else { return }
        momentumLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum(_:)))
        link.add(to: .main, forMode: .common)
        momentumLink = link
    }

    @objc private func stepMomentum(_ link: CADisplayLink) {
        scrollBy(deltaPoints: momentumVelocity * CGFloat(link.duration))
        momentumVelocity *= 0.95
        if abs(momentumVelocity) < 50 { stopMomentum() }
    }

    private func stopMomentum() {
        momentumLink?.invalidate()
        momentumLink = nil
        momentumVelocity = 0
    }

    @objc private func handleTap() { becomeFirstResponder() }

    // MARK: Keyboard input

    public override var canBecomeFirstResponder: Bool { true }

    /// On iPad the floating in-app keyboard is the input, so suppress the docked system
    /// keyboard (a zero-size inputView) while staying first responder for hardware keys.
    /// iPhone keeps the system keyboard (nil → default).
    private let keyboardSuppressor = UIView(frame: .zero)
    public override var inputView: UIView? {
        UIDevice.current.userInterfaceIdiom == .pad ? keyboardSuppressor : nil
    }

    public var keyboardType: UIKeyboardType { .asciiCapable }
    public var autocorrectionType: UITextAutocorrectionType { .no }
    public var autocapitalizationType: UITextAutocapitalizationType { .none }
    public var smartQuotesType: UITextSmartQuotesType { .no }
    public var smartDashesType: UITextSmartDashesType { .no }
    public var spellCheckingType: UITextSpellCheckingType { .no }

    public var hasText: Bool { true }

    public func insertText(_ text: String) {
        switch text {
        case "\n", "\r": onSpecialKey?(.enter, [])
        case "\t":       onSpecialKey?(.tab, [])
        default:         onText?(text, [])
        }
    }

    public func deleteBackward() { onSpecialKey?(.backspace, []) }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let mods = Self.modifiers(from: key.modifierFlags)
            if let special = Self.specialKey(for: key.keyCode) {
                onSpecialKey?(special, mods); handled = true
            } else if mods.contains(.control) {
                let chars = key.charactersIgnoringModifiers
                if !chars.isEmpty { onText?(chars, mods); handled = true }
            } else if !key.characters.isEmpty {
                onText?(key.characters, mods); handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    private static func modifiers(from flags: UIKeyModifierFlags) -> KeyModifiers {
        var mods: KeyModifiers = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.alternate) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        return mods
    }

    private static func specialKey(for code: UIKeyboardHIDUsage) -> TerminalKey? {
        switch code {
        case .keyboardReturnOrEnter, .keypadEnter: return .enter
        case .keyboardDeleteOrBackspace:           return .backspace
        case .keyboardTab:                         return .tab
        case .keyboardEscape:                      return .escape
        case .keyboardDeleteForward:               return .delete
        case .keyboardUpArrow:                     return .arrowUp
        case .keyboardDownArrow:                   return .arrowDown
        case .keyboardLeftArrow:                   return .arrowLeft
        case .keyboardRightArrow:                  return .arrowRight
        case .keyboardHome:                        return .home
        case .keyboardEnd:                         return .end
        case .keyboardPageUp:                      return .pageUp
        case .keyboardPageDown:                    return .pageDown
        default:                                   return nil
        }
    }
}
#endif
