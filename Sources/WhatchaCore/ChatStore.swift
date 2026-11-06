import Foundation

public struct ChatSnapshot: Codable, Equatable {
    public var lines: [Line] = []
    public var sessionID: String?
    public var title = "小乐"
    public init() {}
}

public struct ChatStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> ChatSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return ChatSnapshot() }
        return try! JSONDecoder().decode(ChatSnapshot.self, from: Data(contentsOf: url))
    }
    public func save(_ snapshot: ChatSnapshot) {
        try! JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
