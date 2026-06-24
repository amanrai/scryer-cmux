import Foundation
import simd
import ScryerCore

/// Vertex layouts shared with the Metal shaders (see `MetalTerminalRenderer`).
/// Field order/alignment must match the `SolidVertex`/`GlyphVertex` structs in the
/// shader source exactly.
struct SolidVertex {
    var pos: SIMD2<Float>
    var color: SIMD4<Float>
}

struct GlyphVertex {
    var pos: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>
}

struct RenderUniforms {
    var viewport: SIMD2<Float>
}

extension RGBColor {
    var simd: SIMD4<Float> {
        SIMD4<Float>(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
    }
}
