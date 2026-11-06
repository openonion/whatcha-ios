import UIKit
import XCTest

final class AvatarTests: XCTestCase {
    func testParentAvatarResolvesFromAppBundle() {
        let image = UIImage(named: "avatar_parent", in: Bundle.main, compatibleWith: nil)
        XCTAssertNotNil(image?.cgImage)
        XCTAssertEqual(image?.size, CGSize(width: 256, height: 256))
    }

    func testAgentAvatarResolvesFromAppBundle() {
        let image = UIImage(named: "avatar_agent", in: Bundle.main, compatibleWith: nil)
        XCTAssertNotNil(image?.cgImage)
        XCTAssertEqual(image?.size, CGSize(width: 256, height: 256))
    }
}
