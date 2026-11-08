import XCTest
import UIKit

final class LaunchTests: XCTestCase {
    func testUnpairedPasteIsChineseAndDoesNotAskPermission() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-unpaired", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        let paste = app.buttons["pairing-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        // The system owns the accessibility label; VoiceOver reads "Paste".
        print("pairing-paste measured frame: \(paste.frame)")
        XCTAssertEqual(paste.frame.width, 240, accuracy: 1)
        XCTAssertGreaterThanOrEqual(paste.frame.height, 60)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "unpaired"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let points = [(0.5, 0.5), (0.05, 0.5), (0.95, 0.5), (0.5, 0.1),
                      (0.5, 0.9), (0.15, 0.25), (0.85, 0.75)]
        for (index, point) in points.enumerated() {
            if index > 0 {
                app.terminate()
                app.launch()
            }
            XCTAssertFalse(app.staticTexts["没找到口令。回微信长按孩子发的那条，点「复制」，再回来"].exists)
            pasteFreshText(in: app, at: CGVector(dx: point.0, dy: point.1))
        }
        let invalidPaste = XCTAttachment(screenshot: app.screenshot())
        invalidPaste.name = "invalid-paste"
        invalidPaste.lifetime = .keepAlways
        add(invalidPaste)
    }

    private func pasteFreshText(in app: XCUIApplication, at point: CGVector) {
        let paste = app.buttons["pairing-paste"]
        UIPasteboard.general.string = "普通微信消息 \(UUID().uuidString)"
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in paste.isHittable && paste.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        print("pairing-paste tap \(point), measured frame: \(paste.frame)")
        paste.coordinate(withNormalizedOffset: point).tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in springboard.alerts.count + app.alerts.count > 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [permission], timeout: 3), .timedOut)
        XCTAssertTrue(app.staticTexts["没找到口令。回微信长按孩子发的那条，点「复制」，再回来"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "消息").firstMatch.exists)
        print("pairing-paste alerts: \(springboard.alerts.count + app.alerts.count)")
    }

    func testUnpairedLaunchStaysInForeground() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-unpaired"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let leftForeground = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.state != .runningForeground }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [leftForeground], timeout: 3), .timedOut)
        XCTAssertTrue(app.buttons["pairing-paste"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "消息").firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
