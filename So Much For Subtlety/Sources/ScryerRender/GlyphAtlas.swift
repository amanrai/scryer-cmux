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

    /// UV rectangle (0…1) of a cell-box glyph within the atlas texture.
    struct Entry {
        let u0: Float, v0: Float, u1: Float, v1: Float
    }

    let texture: MTLTexture
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

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: atlasSize, height: atlasSize, mipmapped: false)
        descriptor.usage = .shaderRead
        // .managed (discrete-GPU CPU/GPU sync) is macOS-only; iOS has unified memory.
        #if os(macOS)
        descriptor.storageMode = .managed
        #else
        descriptor.storageMode = .shared
        #endif
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        self.texture = texture
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
        // Advance the shelf packer.
        if penX + cellWidth > atlasSize {
            penX = 0
            penY += cellHeight
        }
        guard penY + cellHeight <= atlasSize else { return nil } // atlas full (v1)
        let originX = penX, originY = penY
        penX += cellWidth

        // Manually-managed buffer so the CGContext's backing store stays alive across
        // drawing and the texture upload (a withUnsafeMutableBytes pointer would dangle).
        let bytesPerRow = cellWidth
        let byteCount = cellWidth * cellHeight
        let data = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 1)
        data.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        defer { data.deallocate() }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: data, width: cellWidth, height: cellHeight,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }

        // Glyph color comes from the attributed string (white); CTLineDraw ignores
        // the context fill color.
        let font = font(bold: key.bold, italic: key.italic)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(gray: 1, alpha: 1),
        ]
        let attributed = NSAttributedString(string: key.text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        // CoreGraphics origin is bottom-left; baseline measured from bottom.
        context.textPosition = CGPoint(x: 0, y: baseline)
        CTLineDraw(line, context)

        // Upload this cell box into the atlas.
        let region = MTLRegionMake2D(originX, originY, cellWidth, cellHeight)
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)

        let s = Float(atlasSize)
        return Entry(
            u0: Float(originX) / s,
            v0: Float(originY) / s,
            u1: Float(originX + cellWidth) / s,
            v1: Float(originY + cellHeight) / s
        )
    }
}
