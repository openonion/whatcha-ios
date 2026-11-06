import XCTest
@testable import WhatchaCore

final class AgentProtocolTests: XCTestCase {
    private func link(invite: String? = "test-invite") -> AgentProtocol {
        let pairing = Pairing(agent: "0xagent", invite: invite)
        return AgentProtocol(pairing: pairing, wire: Wire(me: Identity(), agent: pairing.agent), sessionID: "saved")
    }
    func testResumesSavedSessionOnOpen() throws {
        let value = try JSONSerialization.jsonObject(with: Data(link().opened().utf8)) as! Frame
        XCTAssertEqual(value["session_id"] as? String, "saved")
    }
    func testConnectedIncludesSessionAndRunning() throws {
        var link = link()
        XCTAssertEqual(try link.receive(#"{"type":"CONNECTED","session_id":"s1","status":"running"}"#).event,
                       .connected("s1", running: true, history: []))
        XCTAssertEqual(link.sessionID, "s1")
        XCTAssertEqual(try link.receive(#"{"type":"CONNECTED","session_id":"s1","status":"connected"}"#).event,
                       .connected("s1", running: false, history: []))
    }
    func testHistoryFiltersToolsAndThinking() throws {
        var link = link()
        let update = try link.receive(#"{"type":"CONNECTED","session_id":"s","chat_items":[{"type":"user","content":"q"},{"type":"tool_call"},{"type":"thinking"},{"type":"agent","content":"a"}]}"#)
        XCTAssertEqual(update.event, .connected("s", running: false, history: [.init(true, "q"), .init(false, "a")]))
    }
    func testNonTextHistoryDoesNotMatchWaitingLine() throws {
        var link = link()
        let update = try link.receive(#"{"type":"CONNECTED","session_id":"s","chat_items":[{"type":"user","content":[{"text":"q"}]}]}"#)
        XCTAssertEqual(update.event, .connected("s", running: false, history: [.init(true, "")]))
    }
    func testForgottenPhoneReconnectsBeforeRequeueing() throws {
        var link = link()
        let update = try link.receive(#"{"type":"ERROR","message":"authenticate first (send CONNECT)"}"#)
        XCTAssertEqual(update.event, .rejected)
        let value = try JSONSerialization.jsonObject(with: Data(XCTUnwrap(update.outgoing).utf8)) as! Frame
        XCTAssertEqual(value["type"] as? String, "CONNECT")
        XCTAssertEqual(value["session_id"] as? String, "saved")
    }
    func testRefusedInviteClosesSocket() throws {
        var link = link()
        let update = try link.receive(#"{"type":"ERROR","message":"Invalid invite code"}"#)
        XCTAssertEqual(update.event, .refused)
        XCTAssertTrue(update.close)
    }
    func testMissingInviteClosesWithoutSending() throws {
        var link = link(invite: nil)
        let update = try link.receive(#"{"type":"ONBOARD_REQUIRED"}"#)
        XCTAssertEqual(update.event, .refused)
        XCTAssertTrue(update.close)
        XCTAssertNil(update.outgoing)
    }
    func testOnboardingPresentsInvite() throws {
        var link = link()
        let update = try link.receive(#"{"type":"ONBOARD_REQUIRED"}"#)
        let value = try JSONSerialization.jsonObject(with: Data(XCTUnwrap(update.outgoing).utf8)) as! Frame
        XCTAssertEqual(value["type"] as? String, "ONBOARD_SUBMIT")
        XCTAssertEqual((value["payload"] as? Frame)?["invite_code"] as? String, "test-invite")
    }
    func testProfileReplyAndErrorsReachCaller() throws {
        var link = link()
        XCTAssertEqual(try link.receive(#"{"type":"AGENT_PROFILE","name":"小乐"}"#).event, .profile("小乐"))
        XCTAssertEqual(try link.receive(#"{"type":"OUTPUT","result":"在改软件"}"#).event, .reply("在改软件"))
        XCTAssertEqual(try link.receive(#"{"type":"ERROR","message":"failed"}"#).event, .error("failed"))
        XCTAssertEqual(try link.receive(#"{"type":"ERROR"}"#).event, .error(""))
    }
    func testPingSendsPong() throws {
        var link = link()
        XCTAssertEqual(try link.receive(#"{"type":"PING"}"#).outgoing, #"{"type":"PONG"}"#)
    }
    func testUnknownFrameIsIgnored() throws {
        var link = link()
        let update = try link.receive(#"{"type":"FUTURE"}"#)
        XCTAssertNil(update.event)
        XCTAssertNil(update.outgoing)
        XCTAssertFalse(update.close)
    }
    func testMalformedJSONThrows() {
        var link = link()
        XCTAssertThrowsError(try link.receive("bad json"))
    }
}
