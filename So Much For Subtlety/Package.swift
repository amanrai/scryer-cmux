// swift-tools-version: 5.10
import PackageDescription

// So Much For Subtlety — native smux client.
//
// `ScryerCore` is pure Swift (gateway + websocket + models + the terminal-engine
// protocol) with no native dependencies. `ScryerGhostty`/`ScryerRender` add the
// libghostty-vt bridge and the Metal renderer.
//
// The Ghostty VT core is vendored as a multi-platform xcframework (macOS + iOS device
// + iOS simulator), built by `Vendor/libghostty-vt/build-xcframework.sh` (needs zig).
// The same packages therefore build for both macOS (`swift run SoMuchForSubtlety`) and
// iOS (via the Xcode app target, which links these library products).
let package = Package(
    name: "SoMuchForSubtlety",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .executable(name: "SoMuchForSubtlety", targets: ["SoMuchForSubtlety"]),
        .library(name: "ScryerCore", targets: ["ScryerCore"]),
        .library(name: "ScryerGhostty", targets: ["ScryerGhostty"]),
        .library(name: "ScryerRender", targets: ["ScryerRender"]),
    ],
    targets: [
        // Ghostty VT core as a prebuilt multi-platform xcframework (module: CGhosttyVT).
        // Carries vt.h + a CGhosttyVT modulemap, so `import CGhosttyVT` works unchanged
        // and the right slice is linked per platform automatically.
        .binaryTarget(
            name: "CGhosttyVT",
            path: "Vendor/libghostty-vt/GhosttyVT.xcframework"
        ),

        // Pure-Swift, platform-agnostic core. No native deps.
        .target(
            name: "ScryerCore"
        ),

        // Ghostty-backed terminal engine: bridges the C API and owns the VT instance.
        .target(
            name: "ScryerGhostty",
            dependencies: ["ScryerCore", "CGhosttyVT"]
        ),

        // Metal terminal renderer. Consumes `TerminalSnapshot` from ScryerCore only.
        .target(
            name: "ScryerRender",
            dependencies: ["ScryerCore"]
        ),

        // macOS bring-up app (`swift run`). The iOS app is an Xcode target that links
        // the library products above; both share the Sources/SoMuchForSubtlety code.
        .executableTarget(
            name: "SoMuchForSubtlety",
            dependencies: ["ScryerCore", "ScryerGhostty", "ScryerRender"]
        ),

        .testTarget(
            name: "ScryerCoreTests",
            dependencies: ["ScryerCore"]
        ),
    ]
)
