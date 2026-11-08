import Foundation

public struct Pairing: Codable, Equatable {
    public let agent: String
    public let invite: String?
    public private(set) var accepted: Bool = false
    public var relay: URL { URL(string: "wss://oo.openonion.ai")! }

    public init(agent: String, invite: String?) { self.agent = agent; self.invite = invite }

    private enum CodingKeys: String, CodingKey { case agent, invite, accepted }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        agent = try values.decode(String.self, forKey: .agent)
        invite = try values.decodeIfPresent(String.self, forKey: .invite)
        accepted = try values.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
    }

    public func afterConnected() -> Pairing {
        var pairing = self
        pairing.accepted = true
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
    current == nil || (current?.accepted == false && status == .refused)
}

public func pairingAfterPaste(_ current: Pairing?, status: Status, text: String) -> Pairing? {
    canPastePairing(current, status: status) ? Pairing.parse(text) ?? current : current
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
