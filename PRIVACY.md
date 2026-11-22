# Privacy Policy · 隐私政策

Whatcha (在干嘛) · Effective 2026-11-09

[English](#english) · [中文](#中文)

## English

Whatcha lets family members pair and exchange messages. The child can send a reply directly or authorize AI replies based on shared notes. The app has no advertising, analytics or tracking SDK.

**What stays on the phone**

- The conversation: your messages, the agent's replies and the session ID.
- The pairing: the agent's address and the invite code from the 口令.
- The phone's own Ed25519 signing key, created on first launch and kept in the iOS Keychain on this device only.
- Photos and recordings you choose to send are kept with the conversation. The child-side administrator connection is saved in the iOS Keychain on that device only.

iOS may include the conversation and the pairing in your device backup. Deleting the app removes them; iOS may keep the Keychain key, which never leaves the phone.

**The clipboard**

The app reads the clipboard only when you tap the 「粘贴」 button, and only to find the 口令.

**What leaves the phone**

The app connects over an encrypted connection (TLS) to the public relay at oo.openonion.ai, which forwards to your family's agent:

- the phone's public address, derived from its key, and signatures that prove each message came from this phone;
- the agent's address, and the invite code on first connection;
- the messages you send, including selected photos and recorded voice, with timestamps and the session ID.

The relay forwards messages and does not keep their content. Like any server, it sees your IP address while you are connected. Your family's service receives the messages and keeps its conversation copy. Its configured AI and transcription services process relevant messages and authorized shared notes to produce replies or transcripts.

For invitations, direct replies and child management, the app also uses the family's HTTPS service. If the child enables iPhone reminders, that service registers the device token and sends Apple a generic alert. The alert contains no message text or sender name.

**Contact**

Questions or requests: open an issue at https://github.com/openonion/whatcha-ios/issues.

## 中文

「在干嘛」让家人配对和收发消息。孩子可以本人回复，也可以授权 AI 使用共享笔记代答。App 不含广告、统计分析或追踪 SDK。

**留在手机上的**

- 对话：你发的消息、智能体的回复和会话编号。
- 配对：口令里的智能体地址和邀请码。
- 手机自己的 Ed25519 签名密钥，首次打开时生成，只保存在这台设备的 iOS 钥匙串里。
- 选中并发送的照片和录音随会话一起保存在本机。孩子端的管理员连接仅保存在本机 iOS 钥匙串。

iOS 可能把对话和配对放进设备备份。删除 App 会删掉它们；钥匙串里的密钥可能被 iOS 保留，但它从不离开手机。

**剪贴板**

只有你点「粘贴」按钮时，App 才读取剪贴板，而且只用来找口令。

**离开手机的**

App 通过加密连接（TLS）连到公共中继 oo.openonion.ai，再由它转给你家的智能体：

- 由密钥算出的手机公开地址，以及证明每条消息来自这台手机的签名；
- 智能体地址，首次连接时还有邀请码；
- 你发送的消息，包括主动选择的照片和录音，以及时间戳和会话编号。

中继只转发消息，不保存消息内容。连接期间能看到你的 IP 地址。家庭服务会接收消息并保存会话。服务使用其配置的 AI 和转写服务处理相关消息和获准共享的笔记，生成回复或转写结果。

配对邀请、本人回复和孩子端管理也会连接家庭的 HTTPS 服务。孩子开启 iPhone 提醒后，家庭服务会注册设备令牌，并通过 Apple 发送通用提醒。提醒不含消息正文或发件人姓名。

**联系我们**

有问题或请求，请在 https://github.com/openonion/whatcha-ios/issues 提 issue。
