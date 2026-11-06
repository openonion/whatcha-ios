import Foundation

public typealias Frame = [String: Any]
// Android sorts every object key and emits compact UTF-8 without escaping slashes.
public func canonical(_ object: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

public struct Wire {
    let me: Identity
    let agent: String
    let now: () -> Int64
    let nextID: () -> String

    public init(me: Identity, agent: String,
                now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) },
                nextID: @escaping () -> String = { UUID().uuidString.lowercased() }) {
        self.me = me
        self.agent = agent
        self.now = now
        self.nextID = nextID
    }
    public func connect(_ sessionID: String?) -> String {
        let payload: Frame = ["to": agent, "timestamp": now(), "signed_commands": 1]
        var frame: Frame = ["type": "CONNECT", "timestamp": now(), "to": agent,
                            "payload": payload, "from": me.address, "signature": sign(payload)]
        if let sessionID { frame["session_id"] = sessionID }
        return canonical(frame)
    }

    public func input(_ prompt: String) -> String {
        let payload: Frame = ["type": "INPUT", "input_id": nextID(), "prompt": prompt,
                              "timestamp": now(), "nonce": nextID(), "to": agent]
        var frame = payload
        frame["payload"] = payload
        frame["from"] = me.address
        frame["signature"] = sign(payload)
        return canonical(frame)
    }

    public func onboard(_ invite: String) -> String {
        let payload: Frame = ["timestamp": now(), "invite_code": invite, "to": agent]
        return canonical(["type": "ONBOARD_SUBMIT", "payload": payload,
                          "from": me.address, "signature": sign(payload)])
    }

    public func pong() -> String { #"{"type":"PONG"}"# }

    private func sign(_ payload: Frame) -> String { me.sign(Data(canonical(payload).utf8)) }
}
