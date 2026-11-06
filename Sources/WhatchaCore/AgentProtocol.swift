import Foundation

public struct Pairing {
    public let agent: String
    public let invite: String?
    public let relay = URL(string: "wss://oo.openonion.ai/ws/input")!
    public init(agent: String, invite: String?) { self.agent = agent; self.invite = invite }
}

public enum LinkEvent: Equatable {
    case connected(String, running: Bool, history: [HistoryItem])
    case profile(String), reply(String), error(String), rejected, refused
}

public struct LinkUpdate {
    public var event: LinkEvent?
    public var outgoing: String?
    public var close = false
}

public struct AgentProtocol {
    let pairing: Pairing
    let wire: Wire
    public private(set) var sessionID: String?

    public init(pairing: Pairing, wire: Wire, sessionID: String? = nil) {
        self.pairing = pairing; self.wire = wire; self.sessionID = sessionID
    }
    public func opened() -> String { wire.connect(sessionID) }
    public mutating func receive(_ text: String) throws -> LinkUpdate {
        let frame = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! Frame
        switch frame["type"] as? String {
        case "CONNECTED": return connected(frame)
        case "ONBOARD_REQUIRED":
            guard let invite = pairing.invite else { return refused() }
            return LinkUpdate(outgoing: wire.onboard(invite))
        case "AGENT_PROFILE":
            return LinkUpdate(event: (frame["name"] as? String).map(LinkEvent.profile))
        case "PING": return LinkUpdate(outgoing: wire.pong())
        case "OUTPUT": return LinkUpdate(event: .reply(frame["result"] as? String ?? ""))
        case "ERROR": return error(frame["message"] as? String ?? "")
        default: return LinkUpdate()
        }
    }

    private mutating func connected(_ frame: Frame) -> LinkUpdate {
        sessionID = frame["session_id"] as? String ?? sessionID
        let items = (frame["chat_items"] as? [Frame] ?? []).filter {
            $0["type"] as? String == "user" || $0["type"] as? String == "agent"
        }.map { HistoryItem($0["type"] as? String == "user", $0["content"] as? String ?? "") }
        return LinkUpdate(event: .connected(sessionID!, running: frame["status"] as? String == "running", history: items))
    }

    private func error(_ message: String) -> LinkUpdate {
        if message.hasPrefix("Invalid invite code") { return refused() }
        if message.hasPrefix("authenticate first") {
            return LinkUpdate(event: .rejected, outgoing: opened())
        }
        return LinkUpdate(event: .error(message))
    }

    private func refused() -> LinkUpdate { LinkUpdate(event: .refused, close: true) }
}
