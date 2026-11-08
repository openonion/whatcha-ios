# Privacy Policy · 隐私政策

Whatcha (在干嘛) · Effective 2026-11-09

[English](#english) · [中文](#中文)

## English

Whatcha lets a parent chat with their family's own AI agent. It has no accounts, analytics, advertising, tracking or third-party SDKs.

**What stays on the phone**

- The conversation: your messages, the agent's replies and the session ID.
- The pairing: the agent's address and the invite code from the 口令.
- The phone's own Ed25519 signing key, created on first launch and kept in the iOS Keychain on this device only.

iOS may include the conversation and the pairing in your device backup. Deleting the app removes them; iOS may keep the Keychain key, which never leaves the phone.

**The clipboard**

The app reads the clipboard only when you tap the 「粘贴」 button, and only to find the 口令.

**What leaves the phone**

The app connects over an encrypted connection (TLS) to the public relay at oo.openonion.ai, which forwards to your family's agent:

- the phone's public address, derived from its key, and signatures that prove each message came from this phone;
- the agent's address, and the invite code on first connection;
- the messages you type, with timestamps and the session ID.

The relay forwards messages and does not keep their content. Like any server, it sees your IP address while you are connected. Your family's agent receives your messages and keeps the conversation; whoever runs that agent controls that copy.

**Contact**

Questions or requests: open an issue at https://github.com/openonion/whatcha-ios/issues.

## 中文

「在干嘛」让家长和自己家的 AI 智能体聊天。没有账号，没有统计分析、广告、追踪，也不含第三方 SDK。

**留在手机上的**

- 对话：你发的消息、智能体的回复和会话编号。
- 配对：口令里的智能体地址和邀请码。
- 手机自己的 Ed25519 签名密钥，首次打开时生成，只保存在这台设备的 iOS 钥匙串里。

iOS 可能把对话和配对放进设备备份。删除 App 会删掉它们；钥匙串里的密钥可能被 iOS 保留，但它从不离开手机。

**剪贴板**

只有你点「粘贴」按钮时，App 才读取剪贴板，而且只用来找口令。

**离开手机的**

App 通过加密连接（TLS）连到公共中继 oo.openonion.ai，再由它转给你家的智能体：

- 由密钥算出的手机公开地址，以及证明每条消息来自这台手机的签名；
- 智能体地址，首次连接时还有邀请码；
- 你打的消息，以及时间戳和会话编号。

中继只转发消息，不保存消息内容。和所有服务器一样，连接期间它能看到你的 IP 地址。你家的智能体会收到你的消息并保存对话；那份记录由运行这个智能体的人掌管。

**联系我们**

有问题或请求，请在 https://github.com/openonion/whatcha-ios/issues 提 issue。
