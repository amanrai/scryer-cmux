import Foundation
import CoreText
import CoreGraphics
import Metal

#if canImport(AppKit)
import AppKit
#endif

/// Rasterizes monospace glyphs into a single-channel (R8) texture atlas via CoreText.
///
/// Each unique (text, bold, italic) is drawn into a full cell-sized box at a fixed
/// baseline, so the renderer can place it at the cell's pixel origin with no per-glyph
/// bearing math. Good enough for a monospace grid; refined later for wide glyphs.
final class GlyphAtlas {
    struct Key: Hashable {
        let text: String
        let bold: Bool
        let italic: Bool
    }

    /// UV rectangle (0…1) of a cell-box glyph within an atlas texture.
    struct Entry {
        let u0: Float, v0: Float, u1: Float, v1: Float
        let isColor: Bool    // emoji/color glyph → sample `colorTexture`, no fg tint
        let cellsWide: Int   // 1, or 2 for wide (emoji) glyphs
    }

    let texture: MTLTexture        // R8: monochrome glyphs, tinted by the cell fg
    let colorTexture: MTLTexture   // BGRA premultiplied: color emoji, drawn as-is
    let cellWidth: Int
    let cellHeight: Int
    let baseline: CGFloat

    private let device: MTLDevice
    private let atlasSize: Int
    private let regularFont: CTFont
    private let boldFont: CTFont
    private let italicFont: CTFont
    private let boldItalicFont: CTFont

    private var entries: [Key: Entry] = [:]
    private var penX = 0
    private var penY = 0
    private var colorPenX = 0
    private var colorPenY = 0

    init?(device: MTLDevice, fontSize: CGFloat, atlasSize: Int = 2048) {
        self.device = device
        self.atlasSize = atlasSize

        // Match cmux's font chain: JetBrains Mono Nerd Font → JetBrains Mono → system mono.
        let regular = GlyphAtlas.preferredMonospaceFont(size: fontSize)
        self.regularFont = regular
        // Keep terminal text visually light: many prompts mark large spans as bold,
        // but in this renderer bold should read as color emphasis, not heavier strokes.
        self.boldFont = regular
        self.italicFont = GlyphAtlas.derive(regular, traits: .italicTrait, fontSize: fontSize)
        self.boldItalicFont = self.italicFont

        let ascent = CTFontGetAscent(regular)
        let descent = CTFontGetDescent(regular)
        let leading = CTFontGetLeading(regular)
        self.cellHeight = Int((ascent + descent + leading).rounded(.up))
        self.baseline = descent + leading

        // Monospace advance: measure a representative glyph.
        let glyph = CTFontGetGlyphWithName(regular, "M" as CFString)
        var glyphs = [CGGlyph](repeating: glyph, count: 1)
        var advance = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(regular, .horizontal, &glyphs, &advance, 1)
        self.cellWidth = max(1, Int(advance.width.rounded(.up)))

        // .managed (discrete-GPU CPU/GPU sync) is macOS-only; iOS has unified memory.
        func makeAtlas(_ format: MTLPixelFormat) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: atlasSize, height: atlasSize, mipmapped: false)
            d.usage = .shaderRead
            #if os(macOS)
            d.storageMode = .managed
            #else
            d.storageMode = .shared
            #endif
            return device.makeTexture(descriptor: d)
        }
        guard let texture = makeAtlas(.r8Unorm),
              let colorTexture = makeAtlas(.bgra8Unorm)
        else { return nil }
        self.texture = texture
        self.colorTexture = colorTexture
    }

    private static func derive(_ base: CTFont, traits: CTFontSymbolicTraits, fontSize: CGFloat) -> CTFont {
        CTFontCreateCopyWithSymbolicTraits(base, fontSize, nil, traits, traits) ?? base
    }

    /// Resolves the preferred terminal font by family, mirroring cmux's chain. Verifies
    /// the resolved family actually matches (CoreText silently substitutes otherwise).
    private static func preferredMonospaceFont(size: CGFloat) -> CTFont {
        // Slim, strictly-monospaced Nerd Font. JetBrains Mono ships each weight as its
        // own family ("…NFM Light"), so we resolve by weighted family name. Light reads
        // much lighter than Regular; fall back to Regular, then the system mono.
        for weight in ["Thin", "ExtraLight", "Light", "Regular"] {
            for family in monoFamilies(weight: weight) {
                if let font = font(family: family, size: size) { return font }
            }
        }
        return CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)
            ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
    }

    /// Strictly-monospaced Nerd Font family-name candidates for a given weight.
    private static func monoFamilies(weight: String) -> [String] {
        let suffix = weight == "Regular" ? "" : " \(weight)"
        return [
            "JetBrainsMono NFM\(suffix)",
            "JetBrainsMono Nerd Font Mono\(suffix)",
            "JetBrainsMono NF\(suffix)",
            "JetBrains Mono\(suffix)",
        ]
    }

    private static func font(family: String, size: CGFloat) -> CTFont? {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: family] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let resolved = CTFontCopyFamilyName(font) as String
        return resolved.caseInsensitiveCompare(family) == .orderedSame ? font : nil
    }

    /// Look up (rasterizing on first use) the atlas entry for a cell's text.
    func entry(for key: Key) -> Entry? {
        if let cached = entries[key] { return cached }
        guard !key.text.isEmpty else { return nil }
        guard let entry = rasterize(key) else { return nil }
        entries[key] = entry
        return entry
    }

    private func font(bold: Bool, italic: Bool) -> CTFont {
        switch (bold, italic) {
        case (true, true): return boldItalicFont
        case (true, false): return boldFont
        case (false, true): return italicFont
        case (false, false): return regularFont
        }
    }

    private func rasterize(_ key: Key) -> Entry? {
        GlyphAtlas.isColorGlyph(key.text) ? rasterizeColor(key) : rasterizeMono(key)
    }

    /// True for scalars that default to (or are forced into) emoji presentation.
    private static func isColorGlyph(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if scalar.properties.isEmojiPresentation { return true }
            if scalar.value == 0xFE0F { return true }   // VS16 emoji variation selector
        }
        return false
    }

    /// Monochrome glyph → R8 atlas, tinted by the cell fg in the shader.
    private func rasterizeMono(_ key: Key) -> Entry? {
        if penX + cellWidth > atlasSize { penX = 0; penY += cellHeight }
        guard penY + cellHeight <= atlasSize else { return nil }
        let originX = penX, originY = penY
        penX += cellWidth

        let bytesPerRow = cellWidth
        let data = UnsafeMutableRawPointer.allocate(byteCount: cellWidth * cellHeight, alignment: 1)
        data.initializeMemory(as: UInt8.self, repeating: 0, count: cellWidth * cellHeight)
        defer { data.deallocate() }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: data, width: cellWidth, height: cellHeight,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(bold: key.bold, italic: key.italic),
            .foregroundColor: CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: key.text, attributes: attributes))
        context.textPosition = CGPoint(x: 0, y: baseline)
        CTLineDraw(line, context)

        texture.replace(region: MTLRegionMake2D(originX, originY, cellWidth, cellHeight),
                        mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)

        let s = Float(atlasSize)
        return Entry(u0: Float(originX) / s, v0: Float(originY) / s,
                     u1: Float(originX + cellWidth) / s, v1: Float(originY + cellHeight) / s,
                     isColor: false, cellsWide: 1)
    }

    /// Color emoji → BGRA premultiplied atlas, drawn as-is. Emoji are typically wide
    /// (2 cells), so we measure the advance and rasterize into a 1- or 2-cell box.
    private func rasterizeColor(_ key: Key) -> Entry? {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: key.text, attributes: [.font: regularFont]))
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
        let cellsWide = max(1, min(2, Int((CGFloat(advance) / CGFloat(cellWidth)).rounded())))
        let boxWidth = cellsWide * cellWidth

        if colorPenX + boxWidth > atlasSize { colorPenX = 0; colorPenY += cellHeight }
        guard colorPenY + cellHeight <= atlasSize else { return nil }
        let originX = colorPenX, originY = colorPenY
        colorPenX += boxWidth

        let bytesPerRow = boxWidth * 4
        let data = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * cellHeight, alignment: 1)
        data.initializeMemory(as: UInt8.self, repeating: 0, count: bytesPerRow * cellHeight)
        defer { data.deallocate() }

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: data, width: boxWidth, height: cellHeight,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return nil }
        // Center the emoji within its box; CTLineDraw renders Apple Color Emoji in color.
        let inset = (CGFloat(boxWidth) - CGFloat(advance)) / 2
        context.textPosition = CGPoint(x: max(0, inset), y: baseline)
        CTLineDraw(line, context)

        colorTexture.replace(region: MTLRegionMake2D(originX, originY, boxWidth, cellHeight),
                             mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)

        let s = Float(atlasSize)
        return Entry(u0: Float(originX) / s, v0: Float(originY) / s,
                     u1: Float(originX + boxWidth) / s, v1: Float(originY + cellHeight) / s,
                     isColor: true, cellsWide: cellsWide)
    }
}
