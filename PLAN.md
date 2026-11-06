# Plan: Whatcha (在干嘛) for iPhone

The Android app is the reference: [openonion/whatcha-android](https://github.com/openonion/whatcha-android) (branch wechat-look, tag v0.1.8). Read its README.md, SHIP-PLAN.md (backlog and round logs explain every decision), and app/src/main/java/ai/openonion/whatcha/*.kt before writing anything. Behaviour, wording and look must match it; where iOS differs, say so here.

## M1: text chat with 小乐 on the iOS Simulator, end to end

Done when a parent on an iPhone simulator types 「在干嘛」 and 小乐 (the child's agent, through the public relay wss://oo.openonion.ai) answers, in a screen that looks like the Android app (WeChat chat).

1. SwiftUI, iOS 17+, one screen, no menus or settings. Body text 24pt, targets at least 60pt, WeChat colours, bubbles with tails, avatars (teacup for the parent, the robot for 小乐: reuse the Android drawables/PNGs).
2. Identity: an Ed25519 key made on first launch (CryptoKit `Curve25519.Signing`), kept in the Keychain, never shown.
3. Link: port AgentLink.kt and Wire.kt exactly (frames, signing, invite onboarding, session_id, CONNECTED with `chat_items` history, `agentRunning`). `URLSessionWebSocketTask`, no third-party packages. Backoff 5→60 s, 10 s connect deadline, `retryNow` when the app comes back to the foreground, as Android rounds 30–31.
4. Pairing for M1 is build time: `Config.xcconfig` (gitignored; commit `Config.example.xcconfig`) holds `AGENT_ADDRESS` and `INVITE_CODE`, read through Info.plist. iOS cannot carry them inside the signed app the way tools/pack.py does on Android; QR/link pairing is M2.
5. Messages: the queue, the grey spinner while on its way, the red ! with tap to retry, one question at a time, history kept on the phone, the stored answer shown on reopen instead of asking again (Android 34a `afterReconnect`). Title 「小乐(连接中…)」 while connecting, 「对方正在输入...」 only while ONLINE with a sent line, status strip only for trouble (Android `headerTitle`, `statusText`).
6. Tests: XCTest, red before green, for the pure logic ported from Android's unit tests (HeaderTest, Conversation/afterReconnect, backoff, wire frames and signatures). A signature test vector must match what the Android code produces for the same key and frame.
7. Build: `xcodebuild -scheme Whatcha -destination 'platform=iOS Simulator,name=iPhone 15' -derivedDataPath build test`. Simulator only: no signing team, no device build, no TestFlight, no App Store.

Not in M1: voice, photos, read aloud, QR pairing, push, the child/admin side.

## Rules

Commit only to `main` of this repo, English messages, no Co-Authored-By. No try/catch fallbacks that hide errors (let it crash); no Utils/Helpers files; short functions; YAGNI. No real names anywhere (README, code, tests, screenshots, commits). Never touch ~/.co or any signing identity. Do not push; the owner pushes after checking.

End-to-end runs use a separate test agent with its own key, never a family agent. The owner runs it and the simulator check.

## Round log
