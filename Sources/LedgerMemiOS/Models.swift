import Foundation

/// A single piece of recorded knowledge in a workspace.
public struct Memory: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var text: String
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var workspaceId: String

    public init(
        id: String,
        text: String,
        tags: [String],
        createdAt: Date,
        updatedAt: Date,
        workspaceId: String
    ) {
        self.id = id
        self.text = text
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workspaceId = workspaceId
    }

    enum CodingKeys: String, CodingKey {
        case id, text, tags, createdAt, updatedAt, workspaceId
    }
}

public struct SearchHit: Codable, Sendable, Equatable {
    public let memory: Memory
    public let score: Double
    public let highlight: String?

    public init(memory: Memory, score: Double, highlight: String? = nil) {
        self.memory = memory
        self.score = score
        self.highlight = highlight
    }
}

public struct SearchRequest: Codable, Sendable, Equatable {
    public var query: String
    public var topK: Int?
    public var filter: Filter?

    public struct Filter: Codable, Sendable, Equatable {
        public var tags: [String]?
        public init(tags: [String]? = nil) { self.tags = tags }
    }

    public init(query: String, topK: Int? = nil, filter: Filter? = nil) {
        self.query = query
        self.topK = topK
        self.filter = filter
    }
}

public struct CreateMemoryInput: Codable, Sendable, Equatable {
    public var text: String
    public var tags: [String]?
    public var source: String?

    public init(text: String, tags: [String]? = nil, source: String? = nil) {
        self.text = text
        self.tags = tags
        self.source = source
    }
}

public struct UpdateMemoryInput: Codable, Sendable, Equatable {
    public var text: String?
    public var tags: [String]?

    public init(text: String? = nil, tags: [String]? = nil) {
        self.text = text
        self.tags = tags
    }
}

public struct ListResult: Codable, Sendable, Equatable {
    public let memories: [Memory]
    public let nextCursor: String?

    public init(memories: [Memory], nextCursor: String?) {
        self.memories = memories
        self.nextCursor = nextCursor
    }
}

public enum LedgerMemError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfiguration(String)
    case http(status: Int, message: String, code: String?)
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let m): return m
        case .http(let status, let message, _): return "HTTP \(status): \(message)"
        case .decoding(let m): return "Decoding failed: \(m)"
        case .transport(let m): return "Transport error: \(m)"
        }
    }
}
