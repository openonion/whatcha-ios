import XCTest
@testable import WhatchaCore

final class ChatStoreTests: XCTestCase {
    func testReopenKeepsSessionAndUnansweredLineForRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("chat.json")
        let store = ChatStore(url: url)
        XCTAssertEqual(store.load(), ChatSnapshot())
        var snapshot = ChatSnapshot()
        snapshot.title = "小乐"
        snapshot.sessionID = "saved-session"
        snapshot.lines = [Line(fromParent: true, text: "在干嘛", at: 1, delivery: .sent)]
        store.save(snapshot)
        XCTAssertEqual(ChatStore(url: url).load(), snapshot)
        snapshot.lines = snapshot.lines.afterReconnect(agentRunning: false,
            history: [.init(true, "在干嘛"), .init(false, "在改软件")], now: 2)
        store.save(snapshot)
        let reopened = ChatStore(url: url).load()
        XCTAssertEqual(reopened.lines.last?.text, "在改软件")
        XCTAssertNil(reopened.lines.nextToSend())
    }
}
