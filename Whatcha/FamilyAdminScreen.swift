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
        let at: Int64?
    }

    let id: String
    let label: String
    let messages: [Message]
    let parent: String?
}

private struct FamilyOverview: Decodable {
    let members: [FamilyMember]
    let conversations: [FamilyConversation]
    var handoffs: [Handoff]?

    struct Handoff: Decodable, Identifiable {
        let id: Int64
        let parent: String
        let text: String
    }
}

private enum FamilyRequestError: Error { case unauthorized }

private struct FamilyConnection: Codable {
    let url: URL
    let token: String

    private static var key: [String: String] {
        var account = "connection"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-role-picker") {
            account = ProcessInfo.processInfo.environment["WHATCHA_TEST_CHILD_CONNECTION"] ?? "test-picker"
        }
        #endif
        return [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrService as String: "ai.openonion.whatcha.family",
            kSecAttrAccount as String: account
        ]
    }

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
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 401 { throw FamilyRequestError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("childNotificationsToken") private var registeredToken = ""
    @State private var showHandoffs = false
    @State private var requestingNotifications = false
    @State private var resolving: Set<Int64> = []
    @State private var failedHandoffs: Set<Int64> = []
    @State private var resolvedHandoffs: Set<Int64> = []
    @State private var connection = FamilyConnection.load()
    @State private var overview: FamilyOverview?
    @State private var endpoint = ""
    @State private var token = ""
    @State private var label = ""
    @State private var invitation: String?
    @State private var showingInvite = false
    @State private var revoking: FamilyMember?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let connection {
                    if let error {
                        Button { Task { await refresh(connection) } } label: {
                            Label(error, systemImage: "arrow.clockwise").foregroundStyle(.red)
                        }
                        .disabled(busy)
                    }
                    if overview != nil && conversations.isEmpty {
                        invitationSection(connection)
                        messageSection(connection)
                    } else {
                        messageSection(connection)
                        invitationSection(connection)
                    }
                    memberSection
                    Section("设置") {
                        Button(registeredToken.isEmpty ? "开启留言提醒" : "关闭留言提醒") {
                            Task { await toggleNotifications(connection) }
                        }.disabled(busy || requestingNotifications)
                        Button("退出管理员连接") {
                            Task { await disconnect(connection) }
                        }.disabled(busy || requestingNotifications)
                    }
                } else {
                    Section("管理邀请") {
                        FamilyPasteControl(identifier: "family-setup-paste", onPaste: useManagementInvite, onFailure: {
                            error = "没能读取管理邀请，请重新复制后再粘贴。"
                        })
                        .frame(height: 52)
                        .disabled(busy)
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                    Section {
                        TextField("HTTPS 地址", text: $endpoint, prompt: Text("家庭服务地址"))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("family-service-address")
                            .keyboardType(.URL)
                        SecureField("管理员口令", text: $token)
                        Button("连接") { connect() }.disabled(busy || endpoint.isEmpty || token.isEmpty)
                    } header: {
                        Text("手动连接")
                    } footer: {
                        Text("复制完整的管理邀请，或填写家庭服务地址和管理员口令。")
                    }
                }
                if busy { ProgressView() }
                Button("选择身份", action: switchRole).disabled(busy)
            }
            .navigationTitle("家人管理")
            .refreshable { if let connection { await refresh(connection) } }
            .navigationDestination(isPresented: $showHandoffs) {
                List {
                    if overview == nil {
                        if let connection, error != nil {
                            Button("无法加载留言，点此重试") { Task { await refresh(connection) } }
                        } else {
                            ProgressView("正在加载留言")
                        }
                    } else if overview?.handoffs?.isEmpty != false {
                        Text("暂无待处理留言")
                    }
                    ForEach(overview?.handoffs ?? []) { handoff in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(senderName(handoff)).font(.headline)
                            Text(handoff.text)
                            if let conversation = conversations.first(where: { $0.parent == handoff.parent }),
                               let connection {
                                NavigationLink("打开\(conversation.label)的会话") {
                                    FamilyConversationScreen(connection: connection, conversation: conversation)
                                }
                            }
                            if let connection {
                                Button(resolving.contains(handoff.id) ? "正在处理…" :
                                       failedHandoffs.contains(handoff.id) ? "处理失败，点此重试" : "标记已处理") {
                                    Task { await resolve(handoff, connection: connection) }
                                }.disabled(resolving.contains(handoff.id))
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, let connection { Task { await refresh(connection) } }
            }
        }
    }

    private func invitationSection(_ connection: FamilyConnection) -> some View {
        Section("邀请家人") {
            if showingInvite || conversations.isEmpty || invitation != nil {
                TextField("称呼，例如妈妈", text: $label)
                Button("生成配对口令") { createInvitation(connection) }
                    .disabled(busy || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let invitation {
                    ShareLink(item: invitation) { Label("把口令发给家人", systemImage: "square.and.arrow.up") }
                }
            } else {
                Button("添加家人", systemImage: "person.badge.plus") { showingInvite = true }
            }
        }
    }

    private func messageSection(_ connection: FamilyConnection) -> some View {
        Section("消息") {
            Button {
                showHandoffs = true
                Task { await refresh(connection) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("家人留言", value: overview.flatMap { $0.handoffs?.count }.map(String.init) ?? "—")
                    if let newest = overview?.handoffs?.first {
                        Text("\(senderName(newest))：\(newest.text)")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("family-handoffs")
            if overview != nil && conversations.isEmpty { Text("家人配对后，会在这里看到会话。").foregroundStyle(.secondary) }
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
    }

    private func senderName(_ handoff: FamilyOverview.Handoff) -> String {
        overview?.members.first { $0.id == handoff.parent }?.label ?? "家人"
    }

    private var memberSection: some View {
        Section("家人") {
            ForEach(overview?.members ?? []) { member in
                LabeledContent(member.label, value: member.paired ? "已配对" : "待配对")
                    .swipeActions {
                        Button(member.paired ? "解除配对" : "撤销口令", role: .destructive) { revoking = member }
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
        connect(FamilyConnection(url: url, token: token))
    }

    private func useManagementInvite(_ text: String) {
        guard let setup = FamilySetup.parse(text) else {
            error = "没找到管理邀请。请复制包含家庭服务和管理口令的整条消息。"
            return
        }
        connect(FamilyConnection(url: setup.origin, token: setup.token))
    }

    private func connect(_ candidate: FamilyConnection) {
        Task {
            guard !busy else { return }
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
            var update: FamilyOverview = try await connection.request("family")
            update.handoffs?.removeAll { resolvedHandoffs.contains($0.id) }
            overview = update
            error = nil
        } catch FamilyRequestError.unauthorized {
            endLocalConnection()
            if self.connection == nil { error = "管理员口令已失效，请粘贴新的管理邀请。" }
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
        guard resolving.insert(handoff.id).inserted else { return }
        defer { resolving.remove(handoff.id) }
        failedHandoffs.remove(handoff.id)
        do {
            let data = try JSONEncoder().encode(["id": handoff.id])
            let receipt: Receipt = try await connection.request("family/resolve-handoff", body: data)
            guard receipt.id == handoff.id else { throw URLError(.badServerResponse) }
            resolvedHandoffs.insert(handoff.id)
            overview?.handoffs?.removeAll { $0.id == handoff.id }
        } catch {
            failedHandoffs.insert(handoff.id)
        }
    }

    private func disconnect(_ connection: FamilyConnection) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if !registeredToken.isEmpty {
                do { try await setNotification(registeredToken, enabled: false, connection) }
                catch FamilyRequestError.unauthorized {}
            }
            endLocalConnection()
        } catch {
            self.error = "无法退出管理员连接，请检查网络后重试。"
        }
    }

    private func endLocalConnection() {
        guard FamilyConnection.remove() else {
            error = "无法清除管理员连接，请重试。"
            return
        }
        registeredToken = ""
        UIApplication.shared.unregisterForRemoteNotifications()
        self.connection = nil
        overview = nil
        invitation = nil
        resolvedHandoffs = []
        failedHandoffs = []
        error = nil
    }
}

private struct FamilyConversationScreen: View {
    let connection: FamilyConnection
    let conversation: FamilyConversation
    @State private var manual: [ChildMessage] = []
    @State private var hostMessages: [FamilyConversation.Message]?
    @State private var acknowledged: [DisplayMessage] = []
    @State private var draft = ""
    @State private var pending: Outgoing?
    @State private var busy = false
    @State private var error: String?

    private struct Outgoing: Codable {
        var id = UUID().uuidString.lowercased()
        let parent: String
        let text: String
    }

    private struct DisplayMessage: Identifiable {
        let id: String
        let sender: String
        let text: String
        let at: Int64?
    }

    private var messages: [DisplayMessage] {
        let host = (hostMessages ?? conversation.messages).map {
            DisplayMessage(id: "host-\($0.id)", sender: $0.sender == "user" ? conversation.label : "AI 代答",
                           text: $0.text, at: $0.at)
        }
        let sent = manual.map {
            DisplayMessage(id: $0.id.uuidString.lowercased(), sender: "我", text: $0.text, at: $0.at)
        }
        let saved = Set(sent.map(\.id))
        let direct = (sent + acknowledged.filter { !saved.contains($0.id) }).sorted {
            ($0.at ?? 0) < ($1.at ?? 0)
        }
        var ordered: [DisplayMessage] = []
        var next = 0
        for message in host {
            if let at = message.at {
                while next < direct.count, let earlier = direct[next].at, earlier < at {
                    ordered.append(direct[next])
                    next += 1
                }
            }
            ordered.append(message)
        }
        return ordered + direct.dropFirst(next)
    }

    var body: some View {
        List {
            ForEach(messages) { message in row(message.sender, message.text) }
        }
        .defaultScrollAnchor(.bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let parent = conversation.parent {
                VStack(alignment: .leading, spacing: 8) {
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    HStack(alignment: .bottom) {
                        TextField("写给\(conversation.label)", text: $draft, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)
                            .disabled(busy)
                        Button(busy ? "发送中…" : "发送") { Task { await send(parent: parent) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy || !(1...2000).contains(text.count))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
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
            if !acknowledged.contains(where: { $0.id == receipt.id }) {
                acknowledged.append(DisplayMessage(id: receipt.id, sender: "我", text: outgoing.text,
                                                    at: Int64(Date().timeIntervalSince1970 * 1000)))
            }
            try? FileManager.default.removeItem(at: path)
            draft = ""
            pending = nil
            error = nil
            await refresh()
        } catch {
            self.error = "未能确认发送，请点「发送」重试。"
        }
    }
}
