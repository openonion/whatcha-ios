import Foundation
import SwiftUI
import WhatchaCore

@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var snapshot: ChatSnapshot
    @Published private(set) var status: Status
    private let store: ChatStore
    private var link: AgentLink?
    private var reconnectDelay: Double = 5
    private var retry: DispatchWorkItem?
    private var deadline: DispatchWorkItem?

    var lines: [Line] { snapshot.lines }
    var header: String { headerTitle(snapshot.title, lines: lines, status: status) }

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        store = ChatStore(url: directory.appendingPathComponent("chat.json"))
        snapshot = store.load()
        let identity = Identity.loadFromKeychain()
        let pairing = Self.loadPairing()
        status = pairing == nil ? .unpaired : .connecting
        if let pairing {
            link = AgentLink(pairing: pairing, identity: identity, sessionID: snapshot.sessionID)
            link!.onEvent = { [weak self] in self?.received($0) }
            link!.onDisconnected = { [weak self] in self?.disconnected() }
        }
        open()
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, link != nil else { return }
        snapshot.lines.append(Line(fromParent: true, text: prompt, at: now, delivery: .queued))
        save()
        sendQueued()
    }

    func retry(_ line: Line) {
        snapshot.lines = lines.retry(line)
        save()
        sendQueued()
    }

    func cameBack() {
        guard retryNow(status, waiting: retry != nil) else { return }
        retry?.cancel()
        retry = nil
        status = shownOnReturn(status)
        open()
    }

    private func sendQueued() {
        guard status == .online, let line = lines.nextToSend(), link!.send(line.text) else { return }
        snapshot.lines = lines.markSent(line)
        save()
    }

    private func received(_ event: LinkEvent) {
        switch event {
        case .connected(let sessionID, let running, let history):
            snapshot.sessionID = sessionID
            snapshot.lines = lines.afterReconnect(agentRunning: running, history: history, now: now)
            deadline?.cancel()
            deadline = nil
            reconnectDelay = 5
            status = .online
        case .profile(let name): snapshot.title = name
        case .reply(let text):
            snapshot.lines = lines.answerOldest() + [Line(fromParent: false, text: text, at: now)]
        case .error(let message): snapshot.lines = lines.failOldest(message)
        case .rejected: snapshot.lines = lines.requeueSent()
        case .refused: status = .unpaired
        }
        save()
        // A host that forgot us must acknowledge CONNECT before another INPUT.
        if case .rejected = event { return }
        sendQueued()
    }

    private func disconnected() {
        deadline?.cancel()
        deadline = nil
        if status != .unpaired { status = .offline }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retry = nil
            self.reconnectDelay = nextDelay(self.reconnectDelay)
            self.open()
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay, execute: work)
    }

    private func open() {
        guard let link else { return }
        link.open()
        let work = DispatchWorkItem { [weak self] in
            guard let self, giveUpTry(self.status) else { return }
            self.link?.drop()
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + connectDeadline, execute: work)
    }

    private func save() { store.save(snapshot) }
    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static func loadPairing() -> Pairing? {
        let address = Bundle.main.object(forInfoDictionaryKey: "AGENT_ADDRESS") as! String
        let invite = Bundle.main.object(forInfoDictionaryKey: "INVITE_CODE") as! String
        guard !address.isEmpty else { return nil }
        precondition(address.hasPrefix("0x") && address.count == 66, "Set AGENT_ADDRESS in Config.xcconfig")
        return Pairing(agent: address, invite: invite.isEmpty ? nil : invite)
    }
}
