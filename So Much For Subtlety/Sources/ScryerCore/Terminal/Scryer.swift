import Foundation

/// Scryer interaction request delivered over the terminal WebSocket.
///
/// Decoding mirrors gateway-ui's leniency: only `id` is truly required; everything
/// else is optional/defaulted so a test request with a sparse shape still surfaces.
public struct InteractionRequest: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let from: String
    public let kind: String
    public let payload: Payload
    /// receivedAt ?? createdAt ?? updatedAt — used to order interactions by recency.
    public let receivedAt: String?

    public struct Payload: Decodable, Sendable, Equatable {
        public let title: String?
        public let body: String?
        public let choices: [InteractionChoice]?
    }

    private enum CodingKeys: String, CodingKey { case id, from, kind, payload, receivedAt, createdAt, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        from = (try? c.decode(String.self, forKey: .from)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        payload = (try? c.decode(Payload.self, forKey: .payload)) ?? Payload(title: nil, body: nil, choices: nil)
        receivedAt = (try? c.decode(String.self, forKey: .receivedAt))
            ?? (try? c.decode(String.self, forKey: .createdAt))
            ?? (try? c.decode(String.self, forKey: .updatedAt))
    }

    /// Recency key. Timestamp first, then the (UUIDv7, time-sortable) id as tiebreak —
    /// so even when no timestamp is present, ids still order chronologically.
    public var order: InteractionOrder {
        InteractionOrder(time: InteractionRequest.parseTime(receivedAt), id: id)
    }

    private static func parseTime(_ string: String?) -> Double {
        guard let string else { return 0 }
        return ISO8601DateFormatter().date(from: string)?.timeIntervalSince1970 ?? 0
    }
}

/// Total order over interactions by recency (time, then id).
public struct InteractionOrder: Comparable, Sendable {
    public let time: Double
    public let id: String
    public static func < (lhs: InteractionOrder, rhs: InteractionOrder) -> Bool {
        (lhs.time, lhs.id) < (rhs.time, rhs.id)
    }
}

public struct InteractionChoice: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let send: String?
    public let custom: Bool?
}

/// A semantic agent update (the "activity" feed). Lenient decode: only `id` required.
public struct SessionUpdate: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let title: String
    public let body: String
    public let level: String?
    public let receivedAt: String?

    private enum CodingKeys: String, CodingKey { case id, kind, title, body, level, receivedAt, createdAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        level = try? c.decode(String.self, forKey: .level)
        receivedAt = (try? c.decode(String.self, forKey: .receivedAt)) ?? (try? c.decode(String.self, forKey: .createdAt))
    }
}

/// Decoders for the Scryer WS frame envelopes.
public enum ScryerFrame {
    private struct InteractionEnvelope: Decodable { let request: InteractionRequest? }
    private struct ClearEnvelope: Decodable { let requestId: String? }
    private struct ProducerEnvelope: Decodable { let producer: Producer?; struct Producer: Decodable { let from: String? } }
    private struct UpdatesEnvelope: Decodable { let updates: [FailableUpdate]? }

    /// Decodes each update independently so one malformed element doesn't void the batch.
    private struct FailableUpdate: Decodable {
        let value: SessionUpdate?
        init(from decoder: Decoder) throws { value = try? SessionUpdate(from: decoder) }
    }

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
        ((try? JSONDecoder().decode(UpdatesEnvelope.self, from: data))?.updates ?? []).compactMap(\.value)
    }
}

/// Detects pi's interaction-producer marker directly in the terminal byte stream,
/// the same marker the pty server keys on:
/// `@@SCRYER_INTERACTION_PRODUCER_V1@@{…json…}@@END_SCRYER_INTERACTION_PRODUCER@@`.
/// We scan it client-side so "listening" reflects what's actually in terminal state.
public enum ProducerMarker {
    private static let regex = try! NSRegularExpression(
        pattern: "@@SCRYER_INTERACTION_PRODUCER_V1@@(\\{[^@]*\\})@@END_SCRYER_INTERACTION_PRODUCER@@")

    // Mirrors the pty server's normalizeTerminalText: pi renders the marker with ANSI
    // styling and wraps/pads it across terminal rows, so we must strip escape sequences
    // and all whitespace before matching, or the captured JSON won't parse.
    private static let normalizers: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "\u{1b}\\][\\s\\S]*?(?:\u{7}|\u{1b}\\\\)"),  // OSC
        try! NSRegularExpression(pattern: "\u{1b}\\[[0-?]*[ -/]*[@-~]"),               // CSI
        try! NSRegularExpression(pattern: "\u{1b}[@-Z\\\\-_]"),                        // other ESC
        try! NSRegularExpression(pattern: "\\s+"),                                     // whitespace
    ]

    private static func normalize(_ text: String) -> String {
        var s = text
        for re in normalizers {
            let range = NSRange(location: 0, length: (s as NSString).length)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        return s
    }

    /// The producer `from` of the **newest** marker in `text` (by `emittedAt`), or nil.
    /// Extract every marker via regex, JSON-parse each, then keep the most recently
    /// emitted — that's the producer we listen to.
    public static func latestFrom(in text: String) -> String? {
        let normalized = normalize(text)
        let ns = normalized as NSString
        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length))

        var newestFrom: String?
        var newestTime = -Double.greatestFiniteMagnitude
        for match in matches {
            let json = ns.substring(with: match.range(at: 1))
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let from = object["from"] as? String, !from.isEmpty
            else { continue }
            // `>=` so that with equal/absent emittedAt, the later (textually-newer) marker wins.
            let emitted = parseTime(object["emittedAt"] as? String)
            if emitted >= newestTime {
                newestTime = emitted
                newestFrom = from
            }
        }
        return newestFrom
    }

    private static func parseTime(_ string: String?) -> Double {
        guard let string else { return 0 }
        return ISO8601DateFormatter().date(from: string)?.timeIntervalSince1970 ?? 0
    }
}

/// Scryer PM project/ticket models (via the gateway PM proxy).
public struct PmProject: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let slug: String?
    public let description_md: String?
    public let relative_repo_path: String?
    public let remote_repo_url: String?
    public let parent_project_id: String?
    public let created_at: String?
    public let updated_at: String?

    public init(id: String, name: String, slug: String? = nil, description_md: String? = nil,
                relative_repo_path: String? = nil, remote_repo_url: String? = nil,
                parent_project_id: String? = nil, created_at: String? = nil, updated_at: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description_md = description_md
        self.relative_repo_path = relative_repo_path
        self.remote_repo_url = remote_repo_url
        self.parent_project_id = parent_project_id
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

public struct PmTask: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: String?
    public let updated_at: String?
    public let created_at: String?
    public let deleted_at: String?
    public let description_md: String?
    // Board fields (all optional so the existing Scryer picker decode is unaffected).
    public let display_order: Int?
    public let task_type_id: String?
    public let parent_task_id: String?
    public let project_id: String?
    public let tags: [PmTag]?

    public init(id: String, title: String, status: String? = nil, updated_at: String? = nil,
                created_at: String? = nil, deleted_at: String? = nil,
                description_md: String? = nil, display_order: Int? = nil,
                task_type_id: String? = nil, parent_task_id: String? = nil,
                project_id: String? = nil, tags: [PmTag]? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.updated_at = updated_at
        self.created_at = created_at
        self.deleted_at = deleted_at
        self.description_md = description_md
        self.display_order = display_order
        self.task_type_id = task_type_id
        self.parent_task_id = parent_task_id
        self.project_id = project_id
        self.tags = tags
    }

    /// Copy with selected fields replaced — for optimistic board updates (drag/reorder)
    /// before the server round-trip lands.
    public func with(status newStatus: String? = nil, displayOrder newOrder: Int? = nil,
                     projectId newProject: String? = nil) -> PmTask {
        PmTask(id: id, title: title, status: newStatus ?? status, updated_at: updated_at,
               created_at: created_at, deleted_at: deleted_at,
               description_md: description_md, display_order: newOrder ?? display_order,
               task_type_id: task_type_id, parent_task_id: parent_task_id,
               project_id: newProject ?? project_id, tags: tags)
    }
}

/// A tag attached to a PM task. JEPM returns objects; some endpoints may return bare strings,
/// so decode tolerantly.
public struct PmTag: Decodable, Hashable, Sendable {
    public let id: String?
    public let name: String

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self.id = nil
            self.name = name
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
    }
    private enum CodingKeys: String, CodingKey { case id, name }
}

/// A PM task type (category) — carries the swatch color shown on cards.
public struct PmTaskType: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let color: String?
    public let is_default: Bool?
}

/// A comment on a PM task.
public struct PmComment: Decodable, Identifiable, Sendable {
    public let id: String
    public let body_md: String?
    public let author_role: String?
    public let author_instance_key: String?
    public let created_at: String?

    /// Display author: "You" for human, else the instance key.
    public var authorLabel: String {
        author_role == "human" ? "You" : (author_instance_key ?? "agent")
    }
}
