import Foundation
import Metal
import MetalKit
import simd
import ScryerCore

/// GPU renderer for a `TerminalSnapshot`: clears to the default background, draws
/// per-cell background quads, a block cursor, then glyph quads sampled from the
/// `GlyphAtlas`. Shaders are compiled from source at runtime (no metallib bundling).
final class MetalTerminalRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let solidPipeline: MTLRenderPipelineState
    private let glyphPipeline: MTLRenderPipelineState
    private let atlas: GlyphAtlas

    var cellWidth: Int { atlas.cellWidth }
    var cellHeight: Int { atlas.cellHeight }
    var horizontalPadding: Int { 6 }

    struct GridPoint: Equatable { var col: Int; var row: Int }
    struct Selection: Equatable { var anchor: GridPoint; var focus: GridPoint }
    var selection: Selection?

    /// Cursor blink phase, toggled by the view's blink timer.
    var blinkPhaseOn = true
    var hasVisibleCursor: Bool { snapshot.cursorVisible }

    private var snapshot: TerminalSnapshot = .empty

    init?(device: MTLDevice, fontSize: CGFloat, pixelFormat: MTLPixelFormat) {
        self.device = device
        guard
            let queue = device.makeCommandQueue(),
            let atlas = GlyphAtlas(device: device, fontSize: fontSize),
            let library = try? device.makeLibrary(source: MetalTerminalRenderer.shaderSource, options: nil)
        else { return nil }
        self.queue = queue
        self.atlas = atlas

        func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: vertex)
            desc.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = desc.colorAttachments[0]!
            attachment.pixelFormat = pixelFormat
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.sourceAlphaBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: desc)
        }

        do {
            self.solidPipeline = try pipeline("solid_vertex", "solid_fragment")
            self.glyphPipeline = try pipeline("glyph_vertex", "glyph_fragment")
        } catch {
            return nil
        }
    }

    func update(_ snapshot: TerminalSnapshot) {
        self.snapshot = snapshot
    }

    func draw(in view: MTKView) {
        let snapshot = self.snapshot
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = queue.makeCommandBuffer()
        else { return }

        let bg = snapshot.defaultBackground
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(bg.r) / 255, green: Double(bg.g) / 255, blue: Double(bg.b) / 255, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let scale = Float(view.drawableSize.width) / Float(max(1, view.bounds.width))
        var uniforms = RenderUniforms(viewport: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)))

        let cw = Float(cellWidth)
        let ch = Float(cellHeight)
        let xInset = Float(horizontalPadding)
        let cursorOn = snapshot.cursorVisible && blinkPhaseOn

        // --- backgrounds + cursor (solid pass) ---
        var solids: [SolidVertex] = []
        solids.reserveCapacity(snapshot.cells.count * 6 + 6)
        for cell in snapshot.cells {
            guard let bg = cell.background else { continue }
            appendQuad(&solids, x: xInset + Float(cell.col) * cw, y: Float(cell.row) * ch, w: cw, h: ch, color: bg.simd)
        }
        if let selection {
            let selectionColor = SIMD4<Float>(0.910, 0.714, 0.353, 0.28)
            forEachSelectedSpan(selection, cols: snapshot.cols) { row, colStart, colEnd in
                let width = Float(colEnd - colStart + 1) * cw
                appendQuad(&solids, x: xInset + Float(colStart) * cw, y: Float(row) * ch, w: width, h: ch, color: selectionColor)
            }
        }
        if cursorOn {
            appendQuad(&solids, x: xInset + Float(snapshot.cursorCol) * cw, y: Float(snapshot.cursorRow) * ch, w: cw, h: ch, color: snapshot.cursorColor.simd)
        }

        // Vertex arrays exceed setVertexBytes' 4 KB limit, so upload via a buffer.
        // Uniforms (8 bytes) stay inline.
        if !solids.isEmpty,
           let buffer = device.makeBuffer(bytes: solids, length: MemoryLayout<SolidVertex>.stride * solids.count, options: .storageModeShared) {
            encoder.setRenderPipelineState(solidPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: solids.count)
        }

        // --- glyphs ---
        var glyphs: [GlyphVertex] = []
        glyphs.reserveCapacity(snapshot.cells.count * 6)
        for cell in snapshot.cells where !cell.text.isEmpty {
            let key = GlyphAtlas.Key(text: cell.text, bold: cell.flags.contains(.bold), italic: cell.flags.contains(.italic))
            guard let entry = atlas.entry(for: key) else { continue }
            // Inverse the glyph under the block cursor so it stays readable.
            let isCursorCell = cursorOn && cell.col == snapshot.cursorCol && cell.row == snapshot.cursorRow
            let color = isCursorCell ? snapshot.defaultBackground.simd : cell.foreground.simd
            appendGlyphQuad(&glyphs, x: xInset + Float(cell.col) * cw, y: Float(cell.row) * ch, w: cw, h: ch,
                            uv: entry, color: color)
        }

        if !glyphs.isEmpty,
           let buffer = device.makeBuffer(bytes: glyphs, length: MemoryLayout<GlyphVertex>.stride * glyphs.count, options: .storageModeShared) {
            encoder.setRenderPipelineState(glyphPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: glyphs.count)
        }

        _ = scale
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func appendQuad(_ out: inout [SolidVertex], x: Float, y: Float, w: Float, h: Float, color: SIMD4<Float>) {
        let tl = SIMD2<Float>(x, y), tr = SIMD2<Float>(x + w, y)
        let bl = SIMD2<Float>(x, y + h), br = SIMD2<Float>(x + w, y + h)
        out.append(SolidVertex(pos: tl, color: color))
        out.append(SolidVertex(pos: bl, color: color))
        out.append(SolidVertex(pos: br, color: color))
        out.append(SolidVertex(pos: tl, color: color))
        out.append(SolidVertex(pos: br, color: color))
        out.append(SolidVertex(pos: tr, color: color))
    }

    private func appendGlyphQuad(_ out: inout [GlyphVertex], x: Float, y: Float, w: Float, h: Float, uv: GlyphAtlas.Entry, color: SIMD4<Float>) {
        let tl = GlyphVertex(pos: SIMD2(x, y), uv: SIMD2(uv.u0, uv.v0), color: color)
        let tr = GlyphVertex(pos: SIMD2(x + w, y), uv: SIMD2(uv.u1, uv.v0), color: color)
        let bl = GlyphVertex(pos: SIMD2(x, y + h), uv: SIMD2(uv.u0, uv.v1), color: color)
        let br = GlyphVertex(pos: SIMD2(x + w, y + h), uv: SIMD2(uv.u1, uv.v1), color: color)
        out.append(contentsOf: [tl, bl, br, tl, br, tr])
    }

    private func orderedSelection(_ s: Selection) -> (GridPoint, GridPoint) {
        let a = s.anchor, b = s.focus
        if a.row < b.row || (a.row == b.row && a.col <= b.col) { return (a, b) }
        return (b, a)
    }

    /// Invokes `body(row, colStart, colEnd)` for each row span the selection covers,
    /// following linear text flow.
    private func forEachSelectedSpan(_ selection: Selection, cols: Int, _ body: (Int, Int, Int) -> Void) {
        guard cols > 0 else { return }
        let (start, end) = orderedSelection(selection)
        for row in start.row...end.row {
            let colStart = (row == start.row) ? start.col : 0
            let colEnd = (row == end.row) ? end.col : cols - 1
            let clampedStart = max(0, min(colStart, cols - 1))
            let clampedEnd = max(clampedStart, min(colEnd, cols - 1))
            body(row, clampedStart, clampedEnd)
        }
    }

    /// Text under the current selection, extracted from the latest snapshot.
    func selectedText() -> String? {
        guard let selection else { return nil }
        let snapshot = self.snapshot
        guard snapshot.cols > 0 else { return nil }
        var grid: [Int: [Int: String]] = [:]
        for cell in snapshot.cells where !cell.text.isEmpty {
            grid[cell.row, default: [:]][cell.col] = cell.text
        }
        var lines: [String] = []
        forEachSelectedSpan(selection, cols: snapshot.cols) { row, colStart, colEnd in
            var line = ""
            for col in colStart...colEnd { line += grid[row]?[col] ?? " " }
            while line.last == " " { line.removeLast() }
            lines.append(line)
        }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float2 viewport; };

    struct SolidVertex { float2 pos; float4 color; };
    struct SolidOut { float4 position [[position]]; float4 color; };

    vertex SolidOut solid_vertex(uint vid [[vertex_id]],
                                 device const SolidVertex* verts [[buffer(0)]],
                                 constant Uniforms& u [[buffer(1)]]) {
        SolidVertex v = verts[vid];
        float2 ndc = float2(v.pos.x / u.viewport.x * 2.0 - 1.0, 1.0 - v.pos.y / u.viewport.y * 2.0);
        SolidOut o;
        o.position = float4(ndc, 0.0, 1.0);
        o.color = v.color;
        return o;
    }

    fragment float4 solid_fragment(SolidOut in [[stage_in]]) {
        return in.color;
    }

    struct GlyphVertex { float2 pos; float2 uv; float4 color; };
    struct GlyphOut { float4 position [[position]]; float2 uv; float4 color; };

    vertex GlyphOut glyph_vertex(uint vid [[vertex_id]],
                                 device const GlyphVertex* verts [[buffer(0)]],
                                 constant Uniforms& u [[buffer(1)]]) {
        GlyphVertex v = verts[vid];
        float2 ndc = float2(v.pos.x / u.viewport.x * 2.0 - 1.0, 1.0 - v.pos.y / u.viewport.y * 2.0);
        GlyphOut o;
        o.position = float4(ndc, 0.0, 1.0);
        o.uv = v.uv;
        o.color = v.color;
        return o;
    }

    fragment float4 glyph_fragment(GlyphOut in [[stage_in]],
                                   texture2d<float> atlas [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        float a = atlas.sample(s, in.uv).r;
        return float4(in.color.rgb, in.color.a * a * 0.88);
    }
    """
}
