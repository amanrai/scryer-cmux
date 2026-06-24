import XCTest
@testable import ScryerCore

final class GatewayEndpointTests: XCTestCase {
    func testParsesBareHostWithDefaultPort() throws {
        let endpoint = try XCTUnwrap(GatewayEndpoint(rawInput: "machine.tailnet.ts.net"))
        XCTAssertEqual(endpoint.httpBase.absoluteString, "http://machine.tailnet.ts.net:43223")
        XCTAssertEqual(endpoint.wsBase.scheme, "ws")
        XCTAssertEqual(endpoint.displayHost, "machine.tailnet.ts.net")
    }

    func testParsesHostWithExplicitPort() throws {
        let endpoint = try XCTUnwrap(GatewayEndpoint(rawInput: "192.168.0.10:43223"))
        XCTAssertEqual(endpoint.httpBase.port, 43223)
        XCTAssertEqual(endpoint.displayHost, "192.168.0.10")
    }

    func testHttpsUpgradesWebSocketToWSS() throws {
        let endpoint = try XCTUnwrap(GatewayEndpoint(rawInput: "https://example.com:8443"))
        XCTAssertEqual(endpoint.wsBase.scheme, "wss")
        XCTAssertEqual(endpoint.displayHost, "example.com:8443")
    }

    func testBackendScopedRoutes() throws {
        let endpoint = try XCTUnwrap(GatewayEndpoint(rawInput: "host:43223"))
        XCTAssertEqual(endpoint.backendHTTP("m1", "/state").absoluteString,
                       "http://host:43223/api/backends/m1/state")
        XCTAssertEqual(endpoint.backendHTTP(nil, "/state").absoluteString,
                       "http://host:43223/api/state")
        XCTAssertEqual(endpoint.terminalWS("m1", paneId: "pane-x").absoluteString,
                       "ws://host:43223/api/backends/m1/terminal?paneId=pane-x")
    }

    func testRejectsEmptyInput() {
        XCTAssertNil(GatewayEndpoint(rawInput: "   "))
    }
}
