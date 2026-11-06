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

### Round 1 · 2026-11-07 · M1 implementation, simulator acceptance pending

Read the Android README, ship backlog/round evidence (especially 30–31 and 34a), all app Kotlin sources and the relevant unit tests. The reference checkout is `wechat-look`, one documentation commit beyond `v0.1.8`; its app Kotlin sources have no diff from the tag. No Android files were changed.

Built:

- An iOS 17+ SwiftUI iPhone app and shared `Whatcha` Xcode scheme, restricted to the simulator, with no signing team or third-party dependencies. One WeChat-style text screen: scaled 24pt body text, 60pt input/send/retry targets, grey background, green/white bubbles with tails, the Android teacup/robot PNGs, time labels, and a composer that follows the keyboard. The title and trouble strips use Android's wording and state rules.
- A first-launch CryptoKit Ed25519 identity stored silently in Keychain. Build-time pairing comes from ignored `Config.xcconfig` through Info.plist; `Config.example.xcconfig` is prepared as the version-control template. The local ignored config targets the plan's test agent. No existing signing identity or `~/.co` was accessed.
- `URLSessionWebSocketTask` with signed CONNECT/INPUT/ONBOARD_SUBMIT, PING/PONG, invite rejection and host-forgotten handling, saved session ID, profile name, CONNECTED `chat_items` and running status. Retries use 5→10→20→40→60 seconds, a 10-second deadline on every connection attempt, and foreground `retryNow`. Old socket callbacks cannot affect a newer connection.
- An atomically saved conversation with queued/sent/done/failed states, one question per turn, grey delivery indicator, red tap-to-retry mark and failure note. Reopening preserves the session and waiting line; a completed stored answer is recovered rather than asking again, while a running turn stays waiting. Same-question and already-shown-answer guards match Android 34a.
- XCTest coverage shared by an internal iOS framework/test target and a dependency-free Swift package for native macOS execution. Android-generated CONNECT/onboarding/Chinese INPUT fixtures use the deterministic public test seed `00…1f`; fixture generation and reverse verification tools are included.

Red/green evidence (logs retained locally under ignored `build/verification/`):

- Conversation/header/backoff stubs: 31 tests executed, 31 failed assertions; implementation: 31 tests, zero failures.
- Wire/protocol stubs: 53 tests executed, 28 failed assertions. Persistence was also tested against a stub before implementation: its one test failed two assertions for lost session/line and missing recovered answer.
- Final native macOS XCTest run: **54 tests, zero failures** (21 conversation, 6 header, 4 reconnect, 12 protocol, 10 wire/signature, 1 disk-reopen test). The strengthened signature assertions verify both Android's exact fixture signatures and newly generated CryptoKit signatures against identical canonical payload bytes. Reverse verification also passed: Android's actual `canonical()` and Bouncy Castle accepted three Swift-generated frames.
- `xcodebuild -scheme Whatcha -destination 'generic/platform=iOS Simulator' -derivedDataPath build build`: **BUILD SUCCEEDED** for arm64 and x86_64. Generic `build-for-testing`: **TEST BUILD SUCCEEDED**, including the app and all 54 iOS test cases. The built Info.plist contains the local test pairing and iOS 17 minimum. No device build or distribution was attempted.
- `xcrun simctl list runtimes` was rechecked throughout: CoreSimulatorService is inaccessible (`Connection refused` / invalid connection), so no usable runtime/device can be discovered from this session. The requested iPhone 15 test command, with a 5-second destination timeout, could not execute tests because no concrete simulator device was available. **Zero iOS tests executed.** Native XCTest execution does not replace simulator acceptance.

Platform differences:

- M1's empty hint ends 「打字就行」, and there are no voice/photo controls or read-aloud actions, because those features are excluded from this milestone. iOS uses its own keyboard and safe areas.
- CryptoKit randomizes Ed25519 signatures, whereas Android/Bouncy Castle emits deterministic bytes. Therefore byte-identical generated signatures for the same key/frame are incompatible with the required CryptoKit implementation. Payload bytes and the public key match Android exactly; both directions verify. This is documented by [Apple's signature API](https://developer.apple.com/documentation/cryptokit/curve25519/signing/privatekey/signature(for:)). No alternative cryptography or extra package was added to force deterministic output.
- The reused avatar PNGs are direct bundle resources: Xcode's asset-catalog compiler required simulator services even for a generic build. Loading the original PNGs directly permits the required runtime-independent build.

Independent review: an AI reviewer acting as a technology founder with marketing/UI experience inspected the source states for empty/unpaired, connecting, online, queued/sent, failure/retry, offline, recovered answers, long text, large type and keyboard dismissal, then re-reviewed the fixes. **No rendered screen or live flow was inspected.** Findings:

- **P2, bubble width:** the original flexible frame was inside the bubble background, which could stretch short messages and weaken the WeChat visual hierarchy. Moved the constraint to the outer bubble/delivery row. Recheck criterion: 「在干嘛」 and a one-character reply hug their text, multiline messages wrap, delivery marks stay adjacent and tails touch bubbles at normal/large text sizes. Fixed by source; rendered recheck remains open.
- **P2, signature coverage:** initial fixture checks discarded generated CONNECT/onboarding signatures, leaving their signing regressions undetected. Assertions now verify both generated and fixture signatures, and test names describe interoperability accurately. Recheck criterion: invalid signatures must fail for each of the three frame types. The strengthened suite passes; reverse Android verification passes too.
- **P3, first-launch identity:** initial code generated the key only with valid pairing, contrary to the stated first-launch rule. Moved Keychain loading before the pairing branch; final generic build rechecked. Keychain behavior still needs simulator execution.

Could not verify: a parent's actual 「在干嘛」 through the public relay, invite onboarding on the simulator, Keychain persistence/access, rendered bubble geometry/avatars/colors, keyboard and large-text layout, scrolling to long replies, real offline/foreground backoff/deadline timing, failed-message retry, and reopening after the host completes with exactly one INPUT. The owner runs the test agent and simulator check as specified above; those remain the M1 acceptance gate. The host was not started or modified in this round.

Commit restriction: the first red-step `git add` was rejected with `.git/index.lock: Operation not permitted`; this session's filesystem policy makes `.git` read-only and forbids escalation. Therefore **no commits could be created**, and the implementation remains uncommitted on `main`. Red/green runs were still performed in order. Nothing was pushed. Intended small commit sequence: specify queue/reconnect tests → implement queue/reconnect → specify wire/protocol fixtures/tests → implement wire/protocol → specify disk-reopen test → persist history → build simulator chat screen/link/identity → document verification. This sequence is a record of intended boundaries, not a claim of completed commits.

### Round 2 · 2026-11-07 · launch signing, avatars and launcher icon

Read the test engineer's `sprint-1/test-ios.md`, its scratch XCUITest driver and rendered evidence, and rechecked the Android reference sources. The engineer's baseline demonstrates the P0: unsigned builds crash in `SilentIdentity` with Keychain status `-34018`; an ad-hoc build launches and keeps the same identity across six relaunches. That baseline evidence is from the test engineer, not a new successful simulator run in this session.

Changed:

- **P0:** Debug and Release app configurations now use `CODE_SIGNING_ALLOWED = YES`, `CODE_SIGN_IDENTITY = -`, manual signing and an explicitly empty `DEVELOPMENT_TEAM`. The project remains simulator-only. No real signing identity, team, account settings or `~/.co` was accessed or changed.
- Added `WhatchaUITests` to the shared scheme. Its launch smoke test requires foreground launch, observes three seconds without leaving the foreground, and checks that the 「消息」 composer exists and is hittable. It retains a screenshot in the test result. The runner has its own ad-hoc signing, so reverting only the app's signing settings leaves the launch regression observable rather than disabling the runner.
- **P1:** `ChatScreen` now constructs the avatar from `UIImage(named:)` and passes it to SwiftUI's `Image(uiImage:)`. This explicitly resolves the existing loose bundle PNGs. Added two app-hosted tests, in `WhatchaAppTests`, that decode the parent and agent images from the actual app bundle and assert their 256×256 size. The required assets remain fail-fast if missing; no fallback or exception handling was added.
- **P2:** Rasterized Android's actual `ic_launcher_foreground.xml` bubble/tail/three dots over `icon_green` (#07C160). `tools/AppIcon.svg` preserves that artwork with Android adaptive-icon overscan removed for the iOS mask. Added opaque @2x/@3x PNGs for 20, 29, 40 and 60 point icons and wired `CFBundleIcons` to them. Classic bundle icon metadata avoids an asset compiler dependency on the simulator service, which remains inaccessible here. This round uses the brief's permitted bundle-loading alternative for avatars too.

Verification (local logs: ignored `build/verification/round-2/`):

- Added the smoke test **before** changing the app's unsigned settings. Its baseline run (`red-launch.log`) could not execute: CoreSimulatorService returned `Connection refused`, and Xcode could not select a concrete simulator. Consequently this session does **not** establish a runtime red→green result for that test.
- Ran the exact plan command: `xcodebuild -scheme Whatcha -destination 'platform=iOS Simulator,name=iPhone 15' -derivedDataPath build test` (`full-simulator-test.log`). It exited 70 because all three test targets require a concrete simulator and the sandbox cannot reach CoreSimulatorService. **0 simulator tests executed**, both before and after the signing change; no launch, Keychain or rendered acceptance pass is claimed.
- Final `xcodebuild -scheme Whatcha -destination 'generic/platform=iOS Simulator' -derivedDataPath build build-for-testing`: **TEST BUILD SUCCEEDED** for arm64 and x86_64, including **57 compiled tests: 54 core, 2 hosted avatar tests, 1 UI launch smoke test**.
- `codesign --verify --strict` passes for the built app; `codesign -dv` reports **Signature=adhoc, TeamIdentifier=not set**. This verifies the build artifact's signing, not runtime Keychain access.
- Native package run (`swift test --disable-sandbox --cache-path build/swift-cache --config-path build/swift-config --security-path build/swift-security`, with `CLANG_MODULE_CACHE_PATH` inside `build/`): **54 tests, zero failures**. SwiftPM's nested manifest sandbox could not initialize on the first plain `swift test` attempt, hence the package-only sandbox flag; the outer filesystem restrictions remain in force. Native tests do not cover UIKit or replace simulator tests.
- Inspected the built Info.plist and all eight packaged icon dimensions. Decoded Xcode's optimized PNGs with Apple's image tools: both bundled avatars have the same pixels as the original Android images, and all three icon dots survive packaging. Source icons are RGB with no alpha. Plist validation and `git diff --check` pass.

Independent review: a separate AI reviewer acting as a technology founder with marketing/UI experience inspected the test engineer's rendered answered chat with keyboard (`13-answered.png`), offline-strip sequence (`40-hostdown-strip.png`), warm reconnect/history (`44-return-1.png`), Home Screen placeholder (`01-launch-1.png`), Android/iOS comparison, both final avatar assets and the final icon. It also reviewed the signing settings, test targets and resource wiring. **No post-fix rendered app screen or live flow was inspected.** Findings and recheck criteria:

- **P2, icon dots lost during initial rasterization:** the first raster omitted Android's three dots, reducing recognition of an answer in progress. Replaced the vector renderer's problematic relative arc paths with equivalent SVG circles and rasterized again. The reviewer rechecked the final icon; all three dots are visible, and packaged pixels confirm them. Fixed.
- **P0, launch acceptance remains open:** verified ad-hoc artifact and the smoke test address the reported cause. Recheck: the same smoke test must fail with the app's original unsigned settings, then pass with the current settings; relaunches must preserve identity. This sandbox cannot perform that runtime comparison.
- **P1, avatar acceptance remains open:** packaged images and hosted tests address the resource lookup. Recheck: both hosted tests pass and the teacup/robot visibly fill their existing 60pt spaces beside parent/agent messages.
- **P2, Home Screen acceptance remains open:** icon resources and metadata are consistent. Recheck: install the current build and inspect its actual Home Screen icon. No additional significant source issue found.

The supplied baseline supports the existing 24pt typography, bubble sizing, hierarchy, colors and plain connection wording. Remaining rendered gaps include all post-fix states, large Dynamic Type, long-reply scrolling, failed-message retry and keyboard behavior after the fix. The existing test agent was not started, stopped or modified. The owner-shell iPhone 15 run remains the acceptance gate.

Commit restriction: `git add` failed with `.git/index.lock: Operation not permitted`; `.git` is read-only in this sandbox. All Round 2 changes remain uncommitted on `main` (HEAD `d42ad3b`). Intended commit: `Fix simulator launch and restore chat artwork`. Nothing was pushed.
