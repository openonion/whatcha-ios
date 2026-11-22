import CryptoKit
import Foundation
import Security
import SwiftUI
import UserNotifications
import WhatchaCore

private struct FamilyMember: Decodable, Identifiable {
    let id: String
    let label: String
    let paired: Bool
}

private struct FamilyConversation: Decodable, Identifiable {
    struct Message: Decodable, Identifiable {
        let id: String
        let sender: String
        let text: String
    }

    let id: String
    let label: String
    let messages: [Message]
    let parent: String?
}

private struct FamilyOverview: Decodable {
    let members: [FamilyMember]
    let conversations: [FamilyConversation]
    let handoffs: [Handoff]?

    struct Handoff: Decodable, Identifiable {
        let id: Int64
        let parent: String
        let text: String
    }
}

private struct FamilyConnection: Codable {
    let url: URL
    let token: String

    private static let key: [String: String] = [
        kSecClass as String: kSecClassGenericPassword as String,
        kSecAttrService as String: "ai.openonion.whatcha.family",
        kSecAttrAccount as String: "connection"
    ]

    static func load() -> Self? {
        var query: [String: Any] = key
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        var status = SecItemUpdate(Self.key as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry: [String: Any] = Self.key
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(entry as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
    }

    static func remove() -> Bool {
        let status = SecItemDelete(key as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func request<T: Decodable>(_ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        var parts = URLComponents(url: url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { parts?.queryItems = query }
        guard let requestURL = parts?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: requestURL, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let session = URLSession(configuration: .ephemeral, delegate: FamilyRequestDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

final class FamilyRequestDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct FamilyAdminScreen: View {
    let switchRole: () -> Void
    @EnvironmentObject private var notifications: FamilyNotificationDelegate
    @AppStorage("childNotificationsToken") private var registeredToken = ""
    @State private var showHandoffs = false
    @State private var requestingNotifications = false
    @State private var connection = FamilyConnection.load()
    @State private var overview: FamilyOverview?
    @State private var endpoint = ""
    @State private var token = ""
    @State private var label = ""
    @State private var invitation: String?
    @State private var revoking: FamilyMember?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let connection {
                    Section("邀请家人") {
                        TextField("称呼，例如妈妈", text: $label)
                        Button("生成配对口令") { createInvitation(connection) }
                            .disabled(busy || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let invitation {
                            ShareLink(item: invitation) { Label("分享口令", systemImage: "square.and.arrow.up") }
                        }
                    }
                    Section("家人") {
                        if overview?.members.isEmpty == true { Text("还没有家人配对") }
                        ForEach(overview?.members ?? []) { member in
                            LabeledContent(member.label, value: member.paired ? "已配对" : "待配对")
                                .swipeActions {
                                    Button("撤销", role: .destructive) { revoking = member }
                                }
                        }
                    }
                    Section("会话") {
                        if overview != nil && conversations.isEmpty { Text("还没有家人消息") }
                        ForEach(conversations) { conversation in
                            NavigationLink {
                                FamilyConversationScreen(connection: connection, conversation: conversation)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(conversation.label)
                                    if let last = conversation.messages.last {
                                        Text(last.text).lineLimit(1).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("family-conversation-\(conversation.id)")
                        }
                    }
                    Button {
                        showHandoffs = true
                    } label: {
                        LabeledContent("家人留言", value: String(overview?.handoffs?.count ?? 0))
                    }
                    Button(registeredToken.isEmpty ? "开启留言提醒" : "关闭留言提醒") {
                        Task { await toggleNotifications(connection) }
                    }.disabled(busy || requestingNotifications)
                    Button("刷新家人和会话") { Task { await refresh(connection) } }.disabled(busy)
                    Button("退出管理员连接") {
                        Task { await disconnect(connection) }
                    }.disabled(busy || requestingNotifications)
                } else {
                    Section("连接家庭服务") {
                        TextField("HTTPS 地址", text: $endpoint)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("管理员口令", text: $token)
                        Button("连接") { connect() }.disabled(busy || token.isEmpty)
                    }
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                Button("选择身份", action: switchRole).disabled(busy)
            }
            .navigationTitle("家人管理")
            .navigationDestination(isPresented: $showHandoffs) {
                List {
                    if overview?.handoffs?.isEmpty != false { Text("暂无待处理留言") }
                    ForEach(overview?.handoffs ?? []) { handoff in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(handoff.text)
                            if let conversation = conversations.first(where: { $0.parent == handoff.parent }),
                               let connection {
                                NavigationLink("打开\(conversation.label)的会话") {
                                    FamilyConversationScreen(connection: connection, conversation: conversation)
                                }
                                Button("标记已处理") { Task { await resolve(handoff, connection: connection) } }
                            }
                        }
                    }
                }
                .navigationTitle("家人留言")
                .refreshable { if let connection { await refresh(connection) } }
            }
            .alert("撤销家人配对？", isPresented: Binding(
                get: { revoking != nil }, set: { if !$0 { revoking = nil } }
            ), presenting: revoking) { member in
                Button("确认撤销", role: .destructive) {
                    if let connection { Task { await revoke(member, connection: connection) } }
                }
                Button("取消", role: .cancel) {}
            } message: { member in
                Text("\(member.label) 需要新的邀请才能重新配对。")
            }
            .task {
                if let connection {
                    await refresh(connection)
                    if !registeredToken.isEmpty { UIApplication.shared.registerForRemoteNotifications() }
                    if notifications.handoffOpenCount > 0 { showHandoffs = true }
                }
            }
            .onReceive(notifications.$token) { token in
                if let token, let connection, requestingNotifications || !registeredToken.isEmpty {
                    Task { await updateNotificationToken(token, connection: connection) }
                }
            }
            .onChange(of: notifications.registrationFailed) { _, failed in
                if failed {
                    requestingNotifications = false
                    error = "未能注册 iPhone 提醒，请稍后重试。"
                }
            }
            .onChange(of: notifications.handoffOpenCount) { _, _ in
                if let connection {
                    showHandoffs = true
                    Task { await refresh(connection) }
                }
            }
        }
    }

    private var conversations: [FamilyConversation] {
        guard let overview else { return [] }
        let known = Set(overview.conversations.compactMap(\.parent))
        return overview.conversations + overview.members.filter { $0.paired && !known.contains($0.id) }.map {
            FamilyConversation(id: "member-\($0.id)", label: $0.label, messages: [], parent: $0.id)
        }
    }

    private func connect() {
        guard let url = familyHTTPSOrigin(endpoint) else {
            error = "请输入家庭服务的 HTTPS 地址。"
            return
        }
        let candidate = FamilyConnection(url: url, token: token)
        Task {
            busy = true
            defer { busy = false }
            do {
                let result: FamilyOverview = try await candidate.request("family")
                try candidate.save()
                connection = candidate
                overview = result
                token = ""
                endpoint = ""
                error = nil
            } catch {
                self.error = "连接失败。请核对地址、管理员口令和网络。"
            }
        }
    }

    private func refresh(_ connection: FamilyConnection) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            overview = try await connection.request("family")
            error = nil
        } catch {
            overview = nil
            self.error = "无法读取家人和会话。请检查连接后重试。"
        }
    }

    private func createInvitation(_ connection: FamilyConnection) {
        struct Invitation: Decodable { let invitation: String }
        Task {
            busy = true
            invitation = nil
            defer { busy = false }
            do {
                let body = try JSONEncoder().encode(["label": label])
                let result: Invitation = try await connection.request("family/invitations", body: body)
                invitation = result.invitation
                label = ""
                error = nil
                busy = false
                await refresh(connection)
            } catch {
                self.error = "生成口令失败。请刷新家人列表后再试。"
            }
        }
    }

    private func revoke(_ member: FamilyMember, connection: FamilyConnection) async {
        struct Receipt: Decodable { let id: String }
        guard !busy else { return }
        busy = true
        do {
            let body = try JSONEncoder().encode(["id": member.id])
            let receipt: Receipt = try await connection.request("family/revoke", body: body)
            guard receipt.id == member.id else { throw URLError(.badServerResponse) }
            invitation = nil
            busy = false
            await refresh(connection)
        } catch {
            self.error = "撤销失败，请刷新后重试。"
            busy = false
        }
    }

    private func toggleNotifications(_ connection: FamilyConnection) async {
        do {
            if registeredToken.isEmpty {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
                    error = "可在 iPhone 设置中允许「在干嘛」发送提醒。"
                    return
                }
                requestingNotifications = true
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                try await setNotification(registeredToken, enabled: false, connection)
                registeredToken = ""
                UIApplication.shared.unregisterForRemoteNotifications()
            }
        } catch {
            self.error = "无法更新留言提醒，请重试。"
        }
    }

    private func updateNotificationToken(_ token: String, connection: FamilyConnection) async {
        defer { requestingNotifications = false }
        guard token != registeredToken else { return }
        do {
            if !registeredToken.isEmpty { try await setNotification(registeredToken, enabled: false, connection) }
            try await setNotification(token, enabled: true, connection)
            registeredToken = token
            error = nil
        } catch {
            self.error = "提醒未连接到家庭服务，请重试。"
        }
    }

    private func setNotification(_ token: String, enabled: Bool, _ connection: FamilyConnection) async throws {
        struct Registration: Codable { let token: String; let enabled: Bool }
        struct Receipt: Decodable { let enabled: Bool }
        let data = try JSONEncoder().encode(Registration(token: token, enabled: enabled))
        let result: Receipt = try await connection.request("family/notifications", body: data)
        guard result.enabled == enabled else { throw URLError(.badServerResponse) }
    }

    private func resolve(_ handoff: FamilyOverview.Handoff, connection: FamilyConnection) async {
        struct Receipt: Decodable { let id: Int64 }
        do {
            let data = try JSONEncoder().encode(["id": handoff.id])
            let _: Receipt = try await connection.request("family/resolve-handoff", body: data)
            await refresh(connection)
        } catch {
            self.error = "无法更新家人留言，请刷新后重试。"
        }
    }

    private func disconnect(_ connection: FamilyConnection) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if !registeredToken.isEmpty {
                try await setNotification(registeredToken, enabled: false, connection)
                registeredToken = ""
                UIApplication.shared.unregisterForRemoteNotifications()
            }
            guard FamilyConnection.remove() else { throw CocoaError(.fileWriteUnknown) }
            self.connection = nil
            overview = nil
            invitation = nil
            error = nil
        } catch {
            self.error = "无法退出管理员连接，请检查网络后重试。"
        }
    }
}

private struct FamilyConversationScreen: View {
    let connection: FamilyConnection
    let conversation: FamilyConversation
    @State private var manual: [ChildMessage] = []
    @State private var hostMessages: [FamilyConversation.Message]?
    @State private var draft = ""
    @State private var pending: Outgoing?
    @State private var busy = false
    @State private var error: String?

    private struct Outgoing: Codable {
        var id = UUID().uuidString.lowercased()
        let parent: String
        let text: String
    }

    var body: some View {
        List {
            ForEach(hostMessages ?? conversation.messages) { message in
                row(message.sender == "user" ? conversation.label : "AI 代答", message.text)
            }
            ForEach(manual) { message in row("我", message.text) }
            if let parent = conversation.parent {
                TextField("写给\(conversation.label)", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .disabled(busy)
                Button("发送") { Task { await send(parent: parent) } }
                    .disabled(busy || !(1...2000).contains(text.count))
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(conversation.label)
        .refreshable { await refresh() }
        .task {
            if draft.isEmpty, let path = try? pendingURL(),
               let data = try? Data(contentsOf: path),
               let restored = try? JSONDecoder().decode(Outgoing.self, from: data) {
                pending = restored
                draft = restored.text
            }
            await refresh()
        }
    }

    private var text: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func row(_ sender: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sender).font(.caption).foregroundStyle(.secondary)
            Text(text)
        }
    }

    private func refresh() async {
        guard let parent = conversation.parent else { return }
        do {
            var received: [ChildMessage] = []
            var after: Int64 = 0
            while !Task.isCancelled {
                let page: ChildMessagePage = try await connection.request("family/sent-messages", query: [
                    .init(name: "parent", value: parent), .init(name: "after", value: String(after))
                ])
                received += page.messages
                guard page.messages.count == 100, let next = page.messages.last?.sequence, next > after else { break }
                after = next
            }
            let latest: FamilyOverview = try await connection.request("family")
            if !Task.isCancelled {
                manual = received
                hostMessages = latest.conversations.first { $0.id == conversation.id }?.messages
                    ?? latest.conversations.first { $0.parent == parent }?.messages
                    ?? []
            }
        } catch {
            if !Task.isCancelled { self.error = "没能加载本人发出的消息，请下拉重试。" }
        }
    }

    private func pendingURL() throws -> URL {
        guard let parent = conversation.parent else { throw URLError(.badURL) }
        let path = URL.applicationSupportDirectory.appending(path: "FamilyOutbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let identifier = SHA256.hash(data: Data("\(connection.url.absoluteString)\n\(connection.token)\n\(parent)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return path.appending(path: identifier)
    }

    private func send(parent: String) async {
        struct Receipt: Decodable { let id: String }
        guard !busy else { return }
        let outgoing = pending.flatMap { $0.text == text ? $0 : nil } ?? Outgoing(parent: parent, text: text)
        pending = outgoing
        busy = true
        defer { busy = false }
        do {
            let path = try pendingURL()
            let body = try JSONEncoder().encode(outgoing)
            try body.write(to: path, options: [.atomic, .completeFileProtection])
            let receipt: Receipt = try await connection.request("family/child-messages", body: body)
            guard receipt.id == outgoing.id else { throw URLError(.badServerResponse) }
            try FileManager.default.removeItem(at: path)
            draft = ""
            pending = nil
            error = nil
            await refresh()
        } catch {
            self.error = "未能确认发送，请点「发送」重试。"
        }
    }
}
