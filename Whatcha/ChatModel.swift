import Foundation
import SwiftUI
import WhatchaCore

@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var snapshot: ChatSnapshot
    @Published private(set) var status: Status
    @Published private(set) var pairingError: String?
    @Published private(set) var replacingPairing = false
    private let store: ChatStore
    private let pairingStore: PairingStore
    private var pairing: Pairing?
    private let identity: Identity
    private var link: AgentLink?
    private var reconnectDelay: Double = 5
    private var retry: DispatchWorkItem?
    private var deadline: DispatchWorkItem?
    private var replacementName: String?

    var lines: [Line] { snapshot.lines }
    var header: String { headerTitle(snapshot.title, lines: lines, status: status) }
    var needsPairing: Bool { canPastePairing(pairing, status: status) }
    var childMessagesOrigin: URL? { pairing?.accepted == true ? pairing?.familyOrigin : nil }

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #if DEBUG
        let isolated = ProcessInfo.processInfo.environment["WHATCHA_TEST_CHAT_STORE"].flatMap(UUID.init(uuidString:))
        #else
        let isolated: UUID? = nil
        #endif
        let fileName = isolated.map { "test-chat-\($0.uuidString).json" } ?? "chat.json"
        store = ChatStore(url: directory.appendingPathComponent(fileName))
        var saved = store.load()
        saved.title = saved.childName ?? (saved.title == "小乐" ? "孩子" : saved.title)
        snapshot = saved
        identity = Identity.loadFromKeychain()
        status = .unpaired
        #if DEBUG
        let unpairedTest = ProcessInfo.processInfo.arguments.contains("-uitest-unpaired")
        let testSuite = "ai.openonion.whatcha.UITests"
        let defaults = isolated.flatMap { UserDefaults(suiteName: testSuite + "." + $0.uuidString) }
            ?? (unpairedTest ? UserDefaults(suiteName: testSuite)! : .standard)
        if unpairedTest { defaults.removePersistentDomain(forName: testSuite) }
        pairingStore = PairingStore(defaults: defaults)
        if unpairedTest { return }
        #else
        pairingStore = PairingStore()
        #endif
        if let pairing = pairingStore.load() ?? Self.loadConfigPairing() {
            start(pairing)
        }
    }

    func paste(_ text: String) {
        guard needsPairing else { return }
        pairingError = pairingPasteHint(pairing, status: status, text: text)
        if replacingPairing {
            guard pairingError == nil,
                  let proposed = pairingAfterPaste(pairing, status: status, text: text),
                  proposed != pairing else { return }
            replacementName = Pairing.childName(in: text)
            start(proposed)
            return
        }
        guard pairingError == nil,
              let pairing = pairingStore.pair(from: text, status: status),
              pairing != self.pairing else { return }
        snapshot = ChatSnapshot()
        snapshot.childName = Pairing.childName(in: text)
        snapshot.title = snapshot.childName ?? "孩子"
        save()
        start(pairing)
    }

    private func start(_ pairing: Pairing) {
        retry?.cancel()
        retry = nil
        deadline?.cancel()
        deadline = nil
        link?.onDisconnected = nil
        link?.onEvent = nil
        link?.drop()
        self.pairing = pairing
        if pairing.refused && !pairing.accepted {
            status = .refused
            return
        }
        link = AgentLink(pairing: pairing, identity: identity, sessionID: replacingPairing ? nil : snapshot.sessionID,
                         requiresInvitation: replacingPairing)
        link!.onEvent = { [weak self] in self?.received($0) }
        link!.onDisconnected = { [weak self] in self?.disconnected() }
        reconnectDelay = 5
        status = .connecting
        open()
    }

    func send(_ text: String, attachment: ChatAttachment? = nil) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, link != nil else { return }
        snapshot.lines.append(Line(fromParent: true, text: prompt, at: now, delivery: .queued, attachment: attachment))
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

    func checkConnection() {
        if status == .online, lines.contains(where: { $0.delivery == .sent }) {
            link?.drop()
        }
        cameBack()
    }

    func followChildMessages() async {
        struct FamilyAccess: Decodable { let revoked: Bool }
        guard let origin = childMessagesOrigin, let agent = pairing?.agent else { return }
        let session = URLSession(configuration: .ephemeral, delegate: FamilyRequestDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        while !Task.isCancelled, childMessagesOrigin == origin, pairing?.agent == agent {
            var delay = 3
            do {
                let after = lines.childCursor
                let path = origin.appendingPathComponent("family/child-messages")
                var parts = URLComponents(url: path, resolvingAgainstBaseURL: false)!
                parts.queryItems = [.init(name: "after", value: String(after))]
                let timestamp = String(Int64(Date().timeIntervalSince1970))
                let proof = "whatcha-child-messages-v1\n\(agent)\n\(identity.address)\n\(timestamp)\n\(after)"
                var request = URLRequest(url: parts.url!, timeoutInterval: 15)
                request.setValue(identity.address, forHTTPHeaderField: "X-Whatcha-Parent")
                request.setValue(timestamp, forHTTPHeaderField: "X-Whatcha-Time")
                request.setValue(identity.sign(Data(proof.utf8)), forHTTPHeaderField: "X-Whatcha-Signature")
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled, childMessagesOrigin == origin, pairing?.agent == agent else { return }
                let code = (response as? HTTPURLResponse)?.statusCode
                if code == 403, (try? JSONDecoder().decode(FamilyAccess.self, from: data))?.revoked == true {
                    resetPairing(message: "此前的家人配对已撤销，请孩子重新发送口令。")
                    return
                }
                guard code == 200 else { throw URLError(.badServerResponse) }
                let page = try JSONDecoder().decode(ChildMessagePage.self, from: data)
                let combined = lines.addingChildMessages(page.messages)
                if combined.count != lines.count {
                    snapshot.lines = combined
                    save()
                    if page.messages.count == 100 { delay = 0 }
                }
            } catch {
                delay = 10
            }
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    func beginPairingReplacement() {
        replacingPairing = true
        resetPairing()
    }

    func cancelPairingReplacement() {
        guard replacingPairing, let previous = pairingStore.load() else { return }
        replacingPairing = false
        replacementName = nil
        pairingError = nil
        start(previous)
    }

    func needsClipboardRetry() { pairingError = "没能读取口令，请重新复制后再点「粘贴」。" }

    private func resetPairing(message: String? = nil) {
        retry?.cancel()
        retry = nil
        deadline?.cancel()
        deadline = nil
        link?.onDisconnected = nil
        link?.onEvent = nil
        link?.drop()
        link = nil
        pairing = nil
        if !replacingPairing { pairingStore.clear() }
        status = .unpaired
        pairingError = message
    }

    private func sendQueued() {
        guard status == .online, let line = lines.nextToSend(),
              let link, link.send(line.text, attachment: line.attachment) else { return }
        snapshot.lines = lines.markSent(line)
        save()
    }

    private func received(_ event: LinkEvent) {
        if replacingPairing {
            switch event {
            case .connected, .refused: break
            case .error: pairingError = "没能连接到新的家庭服务。可重试或返回原来的聊天。"; return
            default: return
            }
        }
        switch event {
        case .connected(let sessionID, let running, let history):
            if replacingPairing {
                snapshot = ChatSnapshot()
                snapshot.childName = replacementName
                snapshot.title = replacementName ?? "孩子"
                replacingPairing = false
                replacementName = nil
            }
            pairing = pairing!.afterConnected()
            pairingStore.save(pairing!)
            snapshot.sessionID = sessionID
            snapshot.lines = lines.afterReconnect(agentRunning: running, history: history, now: now)
            deadline?.cancel()
            deadline = nil
            reconnectDelay = 5
            status = .online
        case .profile(let name):
            snapshot.title = snapshot.childName ?? (["小乐", "家人"].contains(name) ? "孩子" : name)
        case .reply(let text):
            snapshot.lines = lines.answerOldest() + [Line(fromParent: false, text: text, at: now)]
        case .error(let message): snapshot.lines = lines.failOldest(message)
        case .rejected: snapshot.lines = lines.requeueSent()
        case .refused: refused()
        }
        save()
        // A host that forgot us must acknowledge CONNECT before another INPUT.
        if case .rejected = event { return }
        sendQueued()
    }

    private func refused() {
        pairing = pairing!.afterRefused()
        if !replacingPairing { pairingStore.save(pairing!) }
        status = .refused
        retry?.cancel()
        retry = nil
        deadline?.cancel()
        deadline = nil
    }

    private func disconnected() {
        deadline?.cancel()
        deadline = nil
        guard status != .refused else { return }
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
        guard status != .refused, let link else { return }
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

    private static func loadConfigPairing() -> Pairing? {
        let address = Bundle.main.object(forInfoDictionaryKey: "AGENT_ADDRESS") as! String
        let invite = Bundle.main.object(forInfoDictionaryKey: "INVITE_CODE") as! String
        guard !address.isEmpty else { return nil }
        precondition(address.hasPrefix("0x") && address.count == 66, "Set AGENT_ADDRESS in Config.xcconfig")
        return Pairing(agent: address, invite: invite.isEmpty ? nil : invite).afterConnected()
    }
}
