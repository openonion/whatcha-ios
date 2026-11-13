import Foundation
import WhatchaCore

// One socket. Completion failures are connection events, never silent fallbacks.
@MainActor
final class AgentLink {
    var onEvent: ((LinkEvent) -> Void)?
    var onDisconnected: (() -> Void)?
    private let pairing: Pairing
    private let wire: Wire
    private var protocolState: AgentProtocol
    private let session = URLSession(configuration: .default)
    private var socket: URLSessionWebSocketTask?
    private var heartbeat: Timer?

    init(pairing: Pairing, identity: Identity, sessionID: String?) {
        self.pairing = pairing
        wire = Wire(me: identity, agent: pairing.agent)
        protocolState = AgentProtocol(pairing: pairing, wire: wire, sessionID: sessionID)
    }

    func open() {
        precondition(socket == nil, "Only one connection at a time")
        let task = session.webSocketTask(with: pairing.relay.appendingPathComponent("ws/input"))
        socket = task
        task.resume()
        sendFrame(protocolState.opened(), on: task)
        receive(on: task)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self, weak task] _ in
            guard let link = self, let current = task else { return }
            Task { @MainActor in
                guard link.socket === current else { return }
                current.sendPing { error in
                    if error != nil { Task { @MainActor in link.disconnect(current) } }
                }
            }
        }
    }

    func send(_ prompt: String) -> Bool {
        guard let socket else { return false }
        sendFrame(wire.input(prompt), on: socket)
        return true
    }

    func drop() {
        guard let socket else { return }
        disconnect(socket)
    }

    private func sendFrame(_ frame: String, on task: URLSessionWebSocketTask) {
        task.send(.string(frame)) { [weak self] error in
            if error != nil { Task { @MainActor in self?.disconnect(task) } }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .failure: self.disconnect(task)
                case .success(let message):
                    self.received(message, on: task)
                    if self.socket === task { self.receive(on: task) }
                }
            }
        }
    }

    private func received(_ message: URLSessionWebSocketTask.Message, on task: URLSessionWebSocketTask) {
        guard case .string(let text) = message else { return }
        guard let update = try? protocolState.receive(text) else {
            disconnect(task)
            return
        }
        if let outgoing = update.outgoing { sendFrame(outgoing, on: task) }
        if let event = update.event { onEvent?(event) }
        if update.close { disconnect(task) }
    }

    private func disconnect(_ task: URLSessionWebSocketTask) {
        guard socket === task else { return }
        socket = nil
        heartbeat?.invalidate()
        heartbeat = nil
        task.cancel(with: .goingAway, reason: nil)
        onDisconnected?()
    }
}
