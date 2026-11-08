import XCTest
@testable import WhatchaCore

final class PairingTests: XCTestCase {
    private let code = "#WC1.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKis#"
    private let expected = Pairing(
        agent: "0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
        invite: "ICEiIyQlJicoKSor")

    func testValidCodeDecodesAddressAndToken() throws {
        let pairing = try XCTUnwrap(Pairing.parse(code))
        XCTAssertEqual(pairing, expected)
        XCTAssertEqual(pairing.relay.absoluteString, "wss://oo.openonion.ai")
    }

    func testFindsCodeWrappedInWeChatText() {
        XCTAssertEqual(Pairing.parse("💬「在干嘛」家人口令 \(code)\n长按这条消息，点「复制」，再打开「在干嘛」"), expected)
    }

    func testWrongLengthsAreNotCodes() {
        XCTAssertNil(Pairing.parse(code.replacingOccurrences(of: "Kis#", with: "Ki#")))
        XCTAssertNil(Pairing.parse(code.replacingOccurrences(of: "Kis#", with: "KisA#")))
    }

    func testWrongPrefixesAreNotCodes() {
        for prefix in ["WC2", "wc1", "WC", "WC11"] {
            XCTAssertNil(Pairing.parse(code.replacingOccurrences(of: "WC1", with: prefix)))
        }
    }

    func testRequiresBase64URLWithoutPaddingAndClosingMarker() {
        XCTAssertNil(Pairing.parse(code.replacingOccurrences(of: "AAEC", with: "+/EC")))
        XCTAssertNil(Pairing.parse(code.replacingOccurrences(of: "Kis#", with: "Kis=#")))
        XCTAssertNil(Pairing.parse(String(code.dropLast())))
        XCTAssertNil(Pairing.parse("普通微信消息"))
    }

    func testBase64URLAlphabet() {
        XCTAssertEqual(Pairing.parse("#WC1." + String(repeating: "_", count: 58) + "8#"),
                       Pairing(agent: "0x" + String(repeating: "ff", count: 32),
                               invite: String(repeating: "_", count: 16)))
        XCTAssertEqual(Pairing.parse("#WC1." + String(repeating: "-", count: 58) + "8#")?.invite,
                       String(repeating: "v", count: 16))
    }

    func testAcceptedPairingPersistsAndLaterCodeCannotReplaceIt() {
        withDefaults { defaults, suite in
            let store = PairingStore(defaults: defaults)
            XCTAssertNil(store.load())
            XCTAssertEqual(store.pair(from: code), expected)
            let accepted = expected.afterConnected()
            store.save(accepted)
            let reopened = PairingStore(defaults: UserDefaults(suiteName: suite)!)
            XCTAssertTrue(reopened.load()!.accepted)
            XCTAssertEqual(reopened.load(), accepted)
            let later = "#WC1." + String(repeating: "A", count: 59) + "#"
            XCTAssertEqual(reopened.pair(from: later, status: .refused), accepted)
            XCTAssertEqual(reopened.pair(from: "不是口令", status: .refused), accepted)
            XCTAssertEqual(PairingStore(defaults: defaults).load(), accepted)
        }
    }

    func testCanPasteOnlyWhenMissingOrUnacceptedAndRefused() {
        let accepted = expected.afterConnected()
        for status in Status.allCases {
            XCTAssertTrue(canPastePairing(nil, status: status))
            XCTAssertEqual(canPastePairing(expected, status: status), status == .refused)
            XCTAssertFalse(canPastePairing(accepted, status: status))
        }
    }

    func testRefusedPairingIsReplacedOnlyByValidCode() {
        let later = "#WC1." + String(repeating: "A", count: 59) + "#"
        let replacement = Pairing.parse(later)!
        XCTAssertEqual(pairingAfterPaste(nil, status: .unpaired, text: code), expected)
        XCTAssertEqual(pairingAfterPaste(expected, status: .refused, text: later), replacement)
        XCTAssertEqual(pairingAfterPaste(expected, status: .refused, text: "普通文字"), expected)
        XCTAssertNil(pairingAfterPaste(nil, status: .unpaired, text: "普通文字"))
        XCTAssertFalse(replacement.accepted)
        for status in [Status.connecting, .online, .offline, .unpaired] {
            XCTAssertEqual(pairingAfterPaste(expected, status: status, text: later), expected)
        }
        for status in Status.allCases {
            let accepted = expected.afterConnected()
            XCTAssertEqual(pairingAfterPaste(accepted, status: status, text: later), accepted)
        }
    }

    func testOnlyConnectedMakesPairingPermanent() {
        XCTAssertFalse(expected.accepted)
        let accepted = expected.afterConnected()
        XCTAssertTrue(accepted.accepted)
        XCTAssertEqual(accepted.agent, expected.agent)
        XCTAssertEqual(accepted.invite, expected.invite)
        XCTAssertEqual(accepted.afterConnected(), accepted)
    }

    func testUnacceptedSavedPairingCanBeReplacedAfterRefusal() {
        withDefaults { defaults, suite in
            let store = PairingStore(defaults: defaults)
            XCTAssertEqual(store.pair(from: code), expected)
            let reopened = PairingStore(defaults: UserDefaults(suiteName: suite)!)
            XCTAssertFalse(reopened.load()!.accepted)
            XCTAssertNil(reopened.pair(from: "不是口令", status: .refused))
            XCTAssertEqual(reopened.load(), expected)
            let later = "#WC1." + String(repeating: "A", count: 59) + "#"
            XCTAssertEqual(reopened.pair(from: later, status: .refused), Pairing.parse(later))
            XCTAssertEqual(store.load(), Pairing.parse(later))
        }
    }

    func testLegacyPairingWithoutAcceptedFlagIsNotPermanent() throws {
        let data = Data(#"{"agent":"0xold","invite":"old-ticket"}"#.utf8)
        let pairing = try JSONDecoder().decode(Pairing.self, from: data)
        XCTAssertFalse(pairing.accepted)
        XCTAssertTrue(canPastePairing(pairing, status: .refused))
    }

    func testInvalidPasteDoesNotSavePairing() {
        withDefaults { defaults, _ in
            let store = PairingStore(defaults: defaults)
            XCTAssertNil(store.pair(from: "不是口令"))
            XCTAssertNil(store.load())
            XCTAssertEqual(store.pair(from: code), expected)
        }
    }

    func testParsedTokenIsSubmittedAsInviteCode() throws {
        let pairing = try XCTUnwrap(Pairing.parse(code))
        var link = AgentProtocol(pairing: pairing, wire: Wire(me: Identity(), agent: pairing.agent))
        let outgoing = try XCTUnwrap(link.receive(#"{"type":"ONBOARD_REQUIRED"}"#).outgoing)
        let frame = try JSONSerialization.jsonObject(with: Data(outgoing.utf8)) as! Frame
        XCTAssertEqual(frame["type"] as? String, "ONBOARD_SUBMIT")
        XCTAssertEqual((frame["payload"] as? Frame)?["invite_code"] as? String, expected.invite)
        XCTAssertEqual((frame["payload"] as? Frame)?["to"] as? String, expected.agent)
    }

    private func withDefaults(_ body: (UserDefaults, String) -> Void) {
        let suite = "PairingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults, suite)
    }
}
