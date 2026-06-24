import Foundation

/// Wire protocol for `WS /api/terminal`. Mirrors `gateway-ui/src/TerminalPane.tsx`.
///
/// Frames are JSON text. Terminal bytes travel as JSON strings (UTF-8), exactly as
/// the browser receives them for xterm; we re-encode to UTF-8 bytes for `vt_write`.
public enum TerminalProtocol {

    // MARK: Client → server

    public enum Outbound {
        case input(data: String, paneId: String)
        case paste(text: String, paneId: String)
        case interrupt(paneId: String)
        case resize(cols: Int, rows: Int, paneId: String)
        case interactionResponse(requestId: String, from: String, response: [String: Any], paneId: String)

        public func jsonData() -> Data {
            let object: [String: Any]
            switch self {
            case let .input(data, paneId):
                object = ["type": "input", "data": data, "paneId": paneId]
            case let .paste(text, paneId):
                object = ["type": "paste", "text": text, "paneId": paneId]
            case let .interrupt(paneId):
                object = ["type": "interrupt", "paneId": paneId]
            case let .resize(cols, rows, paneId):
                object = ["type": "resize", "cols": cols, "rows": rows, "paneId": paneId]
            case let .interactionResponse(requestId, from, response, paneId):
                object = ["type": "interaction_response", "request": ["id": requestId, "from": from], "response": response, "paneId": paneId]
            }
            return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        }

        /// Bracketed-paste wrapper, matching the browser's multiline paste path.
        public static func bracketedPaste(_ text: String, paneId: String) -> Outbound {
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            return .paste(text: "\u{1b}[200~\(normalized)\u{1b}[201~", paneId: paneId)
        }
    }

    // MARK: Server → client

    public enum Inbound {
        case output(bytes: [UInt8], isReplay: Bool)
        case status(Status)
        /// Scryer frames (interaction / interaction_clear / interaction_producer /
        /// session_updates); the original frame data is carried for typed decoding.
        case scryer(type: String, data: Data)
        case unknown(type: String)

        public struct Status {
            public let status: String
            public let cols: Int?
            public let rows: Int?
            public let title: String?
            public let producerFrom: String?
        }

        public static func decode(_ data: Data) -> Inbound? {
            guard
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else { return nil }

            switch type {
            case "output":
                let text = object["data"] as? String ?? ""
                let isReplay = object["replay"] as? Bool ?? false
                return .output(bytes: Array(text.utf8), isReplay: isReplay)
            case "status":
                return .status(Status(
                    status: object["status"] as? String ?? "",
                    cols: object["cols"] as? Int,
                    rows: object["rows"] as? Int,
                    title: object["title"] as? String,
                    producerFrom: (object["interactionProducer"] as? [String: Any])?["from"] as? String
                ))
            case "interaction", "interaction_clear", "interaction_producer", "session_updates":
                return .scryer(type: type, data: data)
            default:
                return .unknown(type: type)
            }
        }
    }
}
