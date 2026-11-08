import XCTest
@testable import WhatchaCore

final class HeaderTests: XCTestCase {
    private func lines(_ delivery: Delivery) -> [Line] {
        [Line(fromParent: true, text: "在干嘛", at: 0, delivery: delivery)]
    }
    func testTypingOnlyOnlineWithSentLine() {
        XCTAssertEqual(headerTitle("小乐", lines: lines(.sent), status: .online), "对方正在输入...")
    }
    func testOtherwiseShowsName() {
        for delivery in [Delivery.done, .queued, .failed] {
            XCTAssertEqual(headerTitle("小乐", lines: lines(delivery), status: .online), "小乐")
        }
        XCTAssertEqual(headerTitle("小乐", lines: [], status: .online), "小乐")
    }
    func testConnectingNeverClaimsTyping() {
        for lines in [[], lines(.sent)] {
            XCTAssertEqual(headerTitle("小乐", lines: lines, status: .connecting), "小乐(连接中…)")
        }
    }
    func testOfflineNeverClaimsTyping() {
        XCTAssertEqual(headerTitle("小乐", lines: lines(.sent), status: .offline), "小乐")
    }
    func testOnlyTroubleHasStrip() {
        XCTAssertNil(statusText(.online))
        XCTAssertNil(statusText(.connecting))
        XCTAssertEqual(statusText(.offline), "暂时联系不上，\n稍后会自己重试")
        XCTAssertEqual(statusText(.unpaired), "还没连上，\n请让孩子帮忙看看")
    }
    func testReturnLooksLikeColdOpen() {
        XCTAssertEqual(headerTitle("小乐", lines: [], status: shownOnReturn(.offline)), "小乐(连接中…)")
        XCTAssertNil(statusText(shownOnReturn(.offline)))
    }

    func testNoTypingHintWithoutComposer() {
        for status in Status.allCases {
            let composer = status != .unpaired && status != .refused
            XCTAssertEqual(showsComposer(status), composer)
            XCTAssertEqual(emptyChatHint("小乐", status: status).contains("打字"), composer)
        }
    }
}

final class ReconnectTests: XCTestCase {
    func testBackoffDoublesAndCapsAtMinute() {
        XCTAssertEqual([5.0, 10, 20, 40, 60].map(nextDelay), [10, 20, 40, 60, 60])
    }
    func testReturnRetriesOnlyWhileWaitingAndNotOnline() {
        for status in Status.allCases {
            XCTAssertFalse(retryNow(status, waiting: false))
            XCTAssertEqual(retryNow(status, waiting: true), status != .online && status != .refused)
        }
    }
    func testReturnPreservesUnpairedAndOnline() {
        XCTAssertEqual(shownOnReturn(.offline), .connecting)
        XCTAssertEqual(shownOnReturn(.unpaired), .unpaired)
        XCTAssertEqual(shownOnReturn(.online), .online)
    }
    func testEveryTryHasTenSecondDeadlineUntilOnline() {
        XCTAssertEqual(connectDeadline, 10)
        for status in Status.allCases { XCTAssertEqual(giveUpTry(status), status != .online) }
    }
}
