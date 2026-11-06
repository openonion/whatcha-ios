import CryptoKit
import XCTest
@testable import WhatchaCore

final class WireTests: XCTestCase {
    private let me = try! Identity(seed: Data(0..<32))
    private func wire(nextID: @escaping () -> String = { "test-id" }) -> Wire {
        Wire(me: me, agent: "0xagent", now: { 1_700_000_000 }, nextID: nextID)
    }
    private func frame(_ text: String) throws -> Frame {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? Frame)
    }
    private func vectors() throws -> [Frame] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: WireTests.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "android-wire-vector", withExtension: "jsonl"))
        return try String(contentsOf: url).split(separator: "\n").map { try frame(String($0)) }
    }
    private func matches(_ actual: String, _ expected: Frame) throws {
        var actualFrame = try frame(actual)
        var expectedFrame = expected
        let androidSignature = expectedFrame.removeValue(forKey: "signature") as! String
        let swiftSignature = actualFrame.removeValue(forKey: "signature") as! String
        XCTAssertEqual(canonical(actualFrame), canonical(expectedFrame))
        let payload = try XCTUnwrap(actualFrame["payload"] as? Frame)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: me.seedPublicKey)
        let bytes = Data(canonical(payload).utf8)
        XCTAssertTrue(key.isValidSignature(unhex(androidSignature), for: bytes))
        XCTAssertTrue(key.isValidSignature(unhex(swiftSignature), for: bytes))
    }
    private func unhex(_ text: String) -> Data {
        Data(stride(from: 0, to: text.count, by: 2).map { offset in
            let start = text.index(text.startIndex, offsetBy: offset)
            return UInt8(text[start..<text.index(start, offsetBy: 2)], radix: 16)!
        })
    }
    func testCanonicalMatchesAndroidAndPython() throws {
        let object = try frame(#"{"to":"0xa","prompt":"吃了吗","timestamp":1}"#)
        XCTAssertEqual(canonical(object), #"{"prompt":"吃了吗","timestamp":1,"to":"0xa"}"#)
    }
    func testCanonicalSortsNestedKeysAndDoesNotEscapeSlash() throws {
        let object = try frame(#"{"z":[{"b":"https://a/吃","a":"\n\"\\"}],"a":true}"#)
        XCTAssertEqual(canonical(object), #"{"a":true,"z":[{"a":"\n\"\\","b":"https://a/吃"}]}"#)
    }
    func testAddressMatchesAndroid() {
        XCTAssertEqual(me.address, "0x03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8")
    }
    func testConnectMatchesAndroidPayloadAndBothSignaturesVerify() throws {
        try matches(wire().connect("saved"), vectors()[0])
    }
    func testOnboardMatchesAndroidPayloadAndBothSignaturesVerify() throws {
        try matches(wire().onboard("test-invite"), vectors()[1])
    }
    func testInputMatchesAndroidPayloadAndBothSignaturesVerify() throws {
        let expected = try vectors()[2]
        var ids = [expected["input_id"] as! String, expected["nonce"] as! String]
        try matches(wire(nextID: { ids.removeFirst() }).input("最近忙啥呢"), expected)
    }
    func testInputSignatureVerifiesAndCoversPrompt() throws {
        let value = try frame(wire().input("在干嘛"))
        let payload = try XCTUnwrap(value["payload"] as? Frame)
        XCTAssertEqual(payload["type"] as? String, "INPUT")
        XCTAssertNil(payload["files"])
        XCTAssertNil(payload["images"])
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: me.seedPublicKey)
        let signature = try XCTUnwrap(value["signature"] as? String)
        let bytes = unhex(signature)
        XCTAssertTrue(publicKey.isValidSignature(bytes, for: Data(canonical(payload).utf8)))
        var changed = payload
        changed["prompt"] = "changed"
        XCTAssertFalse(publicKey.isValidSignature(bytes, for: Data(canonical(changed).utf8)))
    }
    func testFreshIDsForEachInputAndNonce() throws {
        let live = Wire(me: me, agent: "0xagent")
        let a = try frame(live.input("a")), b = try frame(live.input("b"))
        XCTAssertNotEqual(a["input_id"] as? String, b["input_id"] as? String)
        XCTAssertNotEqual(a["nonce"] as? String, b["nonce"] as? String)
    }
    func testConnectOmitsAbsentSession() throws {
        XCTAssertNil(try frame(wire().connect(nil))["session_id"])
    }
    func testPongIsUnsigned() { XCTAssertEqual(wire().pong(), #"{"type":"PONG"}"#) }
}

private extension Identity {
    var seedPublicKey: Data {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation
    }
}
