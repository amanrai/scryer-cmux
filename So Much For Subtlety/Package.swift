// swift-tools-version: 5.10
import PackageDescription

// So Much For Subtlety — native smux client.
//
// `ScryerCore` is pure Swift (gateway + websocket + models + the terminal-engine
// protocol) and builds with no native dependencies, so backend-selection work is
// verifiable before libghostty-vt is vendored:
//
//     swift build --target ScryerCore
//
// The full app additionally requires the libghostty-vt static lib + header, which
// `Vendor/libghostty-vt/build.sh` produces (needs `zig` on PATH).
let package = Package(
    name: "SoMuchForSubtlety",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "SoMuchForSubtlety", targets: ["SoMuchForSubtlety"]),
        .library(name: "ScryerCore", targets: ["ScryerCore"]),
    ],
    targets: [
        // C module over the vendored Ghostty VT core. The header + static lib are
        // produced by Vendor/libghostty-vt/build.sh into Vendor/libghostty-vt/{include,lib}.
        .systemLibrary(name: "CGhosttyVT", path: "Sources/CGhosttyVT"),

        // Pure-Swift, platform-agnostic core. No native deps.
        .target(
            name: "ScryerCore"
        ),

        // Ghostty-backed terminal engine: bridges the C API and owns the VT instance.
        .target(
            name: "ScryerGhostty",
            dependencies: ["ScryerCore", "CGhosttyVT"],
            swiftSettings: [
                .unsafeFlags(["-I", "Vendor/libghostty-vt/include"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "Vendor/libghostty-vt/lib"]),
            ]
        ),

        // Metal terminal renderer. Consumes `TerminalSnapshot` from ScryerCore only,
        // so it builds and can be iterated WITHOUT the libghostty-vt binary. The app
        // target wires the engine's snapshots into it.
        .target(
            name: "ScryerRender",
            dependencies: ["ScryerCore"]
        ),

        // macOS bring-up app.
        //
        // Depends only on ScryerCore for now so `swift run SoMuchForSubtlety` builds
        // and shows gateway connect + backend selection + live WebSocket WITHOUT
        // requiring the libghostty-vt binary. Add "ScryerGhostty"/"ScryerRender" here
        // once Vendor/libghostty-vt is built and the terminal view lands.
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
