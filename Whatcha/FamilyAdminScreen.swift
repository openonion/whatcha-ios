import Foundation
import Security
import SwiftUI

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
}

private struct FamilyOverview: Decodable {
    let members: [FamilyMember]
    let conversations: [FamilyConversation]
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

    func request<T: Decodable>(_ path: String, body: Data? = nil) async throws -> T {
        var request = URLRequest(url: url.appendingPathComponent(path), timeoutInterval: 15)
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

private final class FamilyRequestDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct FamilyAdminScreen: View {
    let switchRole: () -> Void
    @State private var connection = FamilyConnection.load()
    @State private var overview: FamilyOverview?
    @State private var endpoint = ""
    @State private var token = ""
    @State private var label = ""
    @State private var invitation: String?
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
                        }
                    }
                    Section("会话") {
                        if overview?.conversations.isEmpty == true { Text("还没有家人消息") }
                        ForEach(overview?.conversations ?? []) { conversation in
                            NavigationLink {
                                List(conversation.messages) { message in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.sender == "user" ? conversation.label : "AI")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(message.text)
                                    }
                                }
                                .navigationTitle(conversation.label)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(conversation.label)
                                    if let last = conversation.messages.last {
                                        Text(last.text).lineLimit(1).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Button("刷新家人和会话") { Task { await refresh(connection) } }.disabled(busy)
                    Button("退出管理员连接") {
                        guard FamilyConnection.remove() else {
                            error = "无法清除管理员连接。请重试。"
                            return
                        }
                        self.connection = nil
                        overview = nil
                        invitation = nil
                    }.disabled(busy)
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
            .task {
                if let connection { await refresh(connection) }
            }
        }
    }

    private func connect() {
        guard let parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", parts.host != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url else {
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
}
