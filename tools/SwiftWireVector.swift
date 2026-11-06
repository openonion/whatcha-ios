// Test seed only. Compile against the macOS XCTest build of WhatchaCore.
import Foundation
import WhatchaCore

let identity = try! Identity(seed: Data(0..<32))
let wire = Wire(me: identity, agent: "0xagent", now: { 1_700_000_000 })
print(wire.connect("saved"))
print(wire.onboard("test-invite"))
print(wire.input("最近忙啥呢"))
