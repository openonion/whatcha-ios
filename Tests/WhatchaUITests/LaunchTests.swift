import XCTest
import UIKit

final class LaunchTests: XCTestCase {
    func testFirstLaunchMakesParentEntryProminentAndChildEntryReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-role-picker"]
        app.launch()
        let parent = app.buttons["我是家长"]
        let child = app.buttons["我是孩子 · 管理家人"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        XCTAssertTrue(child.isHittable)
        XCTAssertGreaterThan(parent.frame.width, child.frame.width)
        XCTAssertGreaterThanOrEqual(child.frame.height, 44)
        keepScreenshot(app, named: "family-role-picker")
        child.tap()
        XCTAssertTrue(app.navigationBars["家人管理"].waitForExistence(timeout: 5))
        app.buttons["选择身份"].tap()
        parent.tap()
        XCTAssertTrue(app.buttons["pairing-paste"].waitForExistence(timeout: 5))
    }

    func testPhysicalDeviceSoftwareStatus() throws {
        guard ProcessInfo.processInfo.environment["WHATCHA_PHYSICAL_REVIEW"] == "1" else {
            throw XCTSkip("Opt-in read-only device check.")
        }
        continueAfterFailure = false
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let general = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "General")).firstMatch
        for _ in 0..<4 {
            if general.exists { break }
            let back = settings.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
        }
        for _ in 0..<4 {
            if general.isHittable { break }
            settings.swipeUp()
        }
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.tap()
        let update = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Software Update")).firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        update.tap()
        // Let the device finish its own update check; do not install or accept
        // any update, terms or credential prompt from this read-only test.
        let checking = settings.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Checking for Update")).firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !checking.exists }, object: nil)
        _ = XCTWaiter.wait(for: [finished], timeout: 30)
        let retryUpdate = settings.buttons["Try Again"]
        if retryUpdate.exists {
            retryUpdate.tap()
            let checked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !checking.exists }, object: nil)
            _ = XCTWaiter.wait(for: [checked], timeout: 30)
        }
        keepScreenshot(settings, named: "physical-software-update-status")
        print(settings.debugDescription)
    }

    func testPhysicalReviewFlow() throws {
        guard ProcessInfo.processInfo.environment["WHATCHA_PHYSICAL_REVIEW"] == "1" else {
            throw XCTSkip("Opt-in live review test; use only the isolated fictional-data service.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        // No DEBUG launch seams: exercise the installed Release build and its
        // normal pairing and persistence. The host supplies the review clipboard.
        app.launch()
        let parent = app.buttons["我是家长"]
        if parent.exists { parent.tap() }
        let paste = app.buttons["pairing-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        keepScreenshot(app, named: "physical-unpaired")
        paste.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowPaste = springboard.buttons["Allow Paste"]
        if allowPaste.waitForExistence(timeout: 3) { allowPaste.tap() }
        let composer = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("在干嘛")
        app.buttons["发送"].tap()
        let firstAnswer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "今天我在图书馆整理读书笔记")).firstMatch
        XCTAssertTrue(firstAnswer.waitForExistence(timeout: 30))
        keepScreenshot(app, named: "physical-first-reply")
        composer.tap()
        composer.typeText("最近怎么样？")
        app.buttons["发送"].tap()
        let secondAnswer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这是小乐的演示回复")).firstMatch
        XCTAssertTrue(secondAnswer.waitForExistence(timeout: 30))
        keepScreenshot(app, named: "physical-second-reply")
        app.terminate()
        app.launch()
        XCTAssertTrue(secondAnswer.waitForExistence(timeout: 15))
        XCTAssertTrue(firstAnswer.exists)
        app.buttons["关于"].tap()
        XCTAssertTrue(app.buttons["隐私政策"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "physical-reopened-privacy")
    }

    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
