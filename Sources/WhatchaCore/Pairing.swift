import Foundation

public struct Pairing: Codable, Equatable {
    public let agent: String
    public let invite: String?
    public private(set) var accepted: Bool = false
    public private(set) var refused: Bool = false
    public var relay: URL { URL(string: "wss://oo.openonion.ai")! }

    public init(agent: String, invite: String?) { self.agent = agent; self.invite = invite }

    private enum CodingKeys: String, CodingKey { case agent, invite, accepted, refused }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        agent = try values.decode(String.self, forKey: .agent)
        invite = try values.decodeIfPresent(String.self, forKey: .invite)
        accepted = try values.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
        refused = try values.decodeIfPresent(Bool.self, forKey: .refused) ?? false
    }

    public func afterConnected() -> Pairing {
        var pairing = self
        pairing.accepted = true
        return pairing
    }

    public func afterRefused() -> Pairing {
        var pairing = self
        if !accepted { pairing.refused = true }
        return pairing
    }

    public static func parse(_ text: String) -> Pairing? {
        guard let range = text.range(of: #"#WC1\.([A-Za-z0-9_-]{59})#"#, options: .regularExpression) else { return nil }
        let payload = text[range].dropFirst(5).dropLast()
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let bytes = Data(base64Encoded: payload + "="), bytes.count == 44 else { return nil }
        let token = bytes.suffix(12).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return Pairing(agent: "0x" + bytes.prefix(32).hex, invite: token)
    }
}

public func canPastePairing(_ current: Pairing?, status: Status) -> Bool {
    current?.accepted != true
}

public func pairingAfterPaste(_ current: Pairing?, status: Status, text: String) -> Pairing? {
    guard canPastePairing(current, status: status), let parsed = Pairing.parse(text) else { return current }
    if parsed.agent == current?.agent && parsed.invite == current?.invite { return current }
    return parsed
}

public func pairingPasteHint(_ current: Pairing?, status: Status, text: String) -> String? {
    guard canPastePairing(current, status: status),
          pairingAfterPaste(current, status: status, text: text) == current else { return nil }
    if Pairing.parse(text) != nil && (current?.refused == true || status == .refused) {
        return "这条口令用过了，请孩子重新发一条"
    }
    if Pairing.parse(text) != nil { return "这条口令收到了，正在连接，请稍等" }
    return "没找到口令。回微信长按孩子发的那条，点「复制」，再回来"
}

public struct PairingStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> Pairing? {
        defaults.data(forKey: "pairing").map { try! JSONDecoder().decode(Pairing.self, from: $0) }
    }

    public func save(_ pairing: Pairing) {
        defaults.set(try! JSONEncoder().encode(pairing), forKey: "pairing")
    }

    public func pair(from text: String, status: Status = .unpaired) -> Pairing? {
        let current = load()
        guard canPastePairing(current, status: status) else { return current }
        guard Pairing.parse(text) != nil else { return nil }
        let pairing = pairingAfterPaste(current, status: status, text: text)!
        save(pairing)
        return pairing
    }
}
