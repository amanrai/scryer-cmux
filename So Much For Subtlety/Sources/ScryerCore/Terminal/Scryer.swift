import Foundation

/// Scryer interaction request delivered over the terminal WebSocket.
public struct InteractionRequest: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let from: String
    public let kind: String
    public let payload: Payload

    public struct Payload: Decodable, Sendable, Equatable {
        public let title: String?
        public let body: String?
        public let choices: [InteractionChoice]?
    }
}

public struct InteractionChoice: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let send: String?
    public let custom: Bool?
}

/// A semantic agent update (the "activity" feed).
public struct SessionUpdate: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let title: String
    public let body: String
    public let level: String?
    public let receivedAt: String?
}

/// Decoders for the Scryer WS frame envelopes.
public enum ScryerFrame {
    private struct InteractionEnvelope: Decodable { let request: InteractionRequest? }
    private struct ClearEnvelope: Decodable { let requestId: String? }
    private struct ProducerEnvelope: Decodable { let producer: Producer?; struct Producer: Decodable { let from: String? } }
    private struct UpdatesEnvelope: Decodable { let updates: [SessionUpdate]? }

    public static func interaction(from data: Data) -> InteractionRequest? {
        (try? JSONDecoder().decode(InteractionEnvelope.self, from: data))?.request
    }
    public static func clearedRequestId(from data: Data) -> String? {
        (try? JSONDecoder().decode(ClearEnvelope.self, from: data))?.requestId
    }
    public static func producer(from data: Data) -> String? {
        (try? JSONDecoder().decode(ProducerEnvelope.self, from: data))?.producer?.from
    }
    public static func updates(from data: Data) -> [SessionUpdate] {
        (try? JSONDecoder().decode(UpdatesEnvelope.self, from: data))?.updates ?? []
    }
}

/// Scryer PM project/ticket models (via the gateway PM proxy).
public struct PmProject: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let slug: String?
    public let relative_repo_path: String?
}

public struct PmTask: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: String?
    public let updated_at: String?
    public let description_md: String?
}
