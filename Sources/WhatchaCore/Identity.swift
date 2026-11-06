import CryptoKit
import Foundation

public struct Identity {
    private let key: Curve25519.Signing.PrivateKey
    public init(seed: Data) throws { key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed) }
    public init() { key = Curve25519.Signing.PrivateKey() }
    public var seed: Data { key.rawRepresentation }
    public var address: String { "0x" + key.publicKey.rawRepresentation.hex }
    public func sign(_ data: Data) -> String { (try! key.signature(for: data)).hex }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
