import XCTest
@testable import WhatchaCore

final class ConversationTests: XCTestCase {
    private func asked(_ text: String, _ delivery: Delivery) -> Line {
        Line(fromParent: true, text: text, at: 0, delivery: delivery)
    }
    private func asked(_ delivery: Delivery) -> Line { asked("在干嘛", delivery) }
    private let history = [HistoryItem(true, "吃了吗"), HistoryItem(false, "不知道"),
                           HistoryItem(true, "在干嘛"), HistoryItem(false, "在改软件")]

    func testSecondQuestionWaits() {
        XCTAssertNil([asked(.sent), asked("b", .queued)].nextToSend())
    }
    func testFirstQueuedGoesNext() {
        XCTAssertEqual([asked(.done), asked("b", .queued), asked("c", .queued)].nextToSend()?.text, "b")
    }
    func testNothingWaiting() { XCTAssertNil([asked(.done), asked(.failed)].nextToSend()) }
    func testReplyAnswersOldestSent() {
        XCTAssertEqual([asked(.sent), asked("b", .sent)].answerOldest().map(\.delivery), [.done, .sent])
    }
    func testRejectionRequeuesOnlySent() {
        XCTAssertEqual([asked(.done), asked(.failed), asked(.sent)].requeueSent().map(\.delivery), [.done, .failed, .queued])
    }
    func testMarksOnlySelectedLine() {
        let lines = [asked(.queued), asked(.queued)]
        XCTAssertEqual(lines.markSent(lines[1]).map(\.delivery), [.queued, .sent])
    }
    func testFailureMarksOldestSent() {
        XCTAssertEqual([asked(.sent), asked(.queued)].failOldest("boom").map(\.delivery), [.failed, .queued])
    }
    func testEmptyRelayErrorChangesNothing() {
        let lines = [asked(.sent)]
        XCTAssertEqual(lines.failOldest(""), lines)
    }
    func testErrorWithoutSentChangesNothing() {
        let lines = [asked(.done)]
        XCTAssertEqual(lines.failOldest("boom"), lines)
    }
    func testRetryInPlace() {
        let lines = [asked(.failed), asked("b", .sent)]
        XCTAssertEqual(lines.retry(lines[0]).map(\.delivery), [.queued, .sent])
    }
    func testOnlyFailureCanRetry() {
        let lines = [asked(.done)]
        XCTAssertEqual(lines.retry(lines[0]), lines)
    }
    func testSuccessfulResendClearsFailure() {
        let failed = [asked(.sent)].failOldest("boom")
        let queued = failed.retry(failed[0])
        XCTAssertEqual(queued.markSent(queued[0]).answerOldest()[0].delivery, .done)
    }
    func testStillRunningKeepsWaiting() {
        let lines = [asked(.sent)]
        XCTAssertEqual(lines.afterReconnect(agentRunning: true, history: history, now: 5), lines)
    }
    func testIdleWithoutAnswerRequeues() {
        XCTAssertEqual([asked(.sent)].afterReconnect(agentRunning: false, history: [], now: 5)[0].delivery, .queued)
    }
    func testStoredAnswerIsShownWithoutResending() {
        let after = [asked(.sent)].afterReconnect(agentRunning: false, history: history, now: 5)
        XCTAssertEqual(after.map(\.delivery), [.done, .done])
        XCTAssertEqual(after.last?.text, "在改软件")
        XCTAssertEqual(after.last?.at, 5)
        XCTAssertNil(after.nextToSend())
    }
    func testNeverArrivedIsAskedAgain() {
        XCTAssertEqual([asked("忙吗", .sent)].afterReconnect(agentRunning: false, history: history, now: 5)[0].delivery, .queued)
    }
    func testIdenticalQuestionDoesNotReuseOldAnswer() {
        let lines = [asked(.done), Line(fromParent: false, text: "在改软件", at: 1), asked(.sent)]
        let after = lines.afterReconnect(agentRunning: false, history: history, now: 5)
        XCTAssertEqual(after.count, 3)
        XCTAssertEqual(after.last?.delivery, .queued)
    }
    func testFailedRunIsAskedAgain() {
        XCTAssertEqual([asked(.sent)].afterReconnect(agentRunning: false, history: Array(history.dropLast()), now: 5)[0].delivery, .queued)
    }
    func testReconnectLeavesFailedForParent() {
        XCTAssertEqual([asked(.failed), asked(.sent)].afterReconnect(agentRunning: false, history: [], now: 5).map(\.delivery), [.failed, .queued])
    }
    func testUsesLastAgentItemAfterLastQuestion() {
        let items = history + [HistoryItem(false, "改好了")]
        XCTAssertEqual([asked(.sent)].afterReconnect(agentRunning: false, history: items, now: 5).last?.text, "改好了")
    }
    func testHistoryRoundTripKeepsDeliveryAndIdentity() throws {
        let lines = [asked(.failed), asked(.sent)]
        XCTAssertEqual(try JSONDecoder().decode([Line].self, from: JSONEncoder().encode(lines)), lines)
    }
}
