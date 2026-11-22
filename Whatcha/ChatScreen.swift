import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import WhatchaCore

private let chatBackground = Color(red: 237/255, green: 237/255, blue: 237/255)
private let barBackground = Color(red: 247/255, green: 247/255, blue: 247/255)
private let parentGreen = Color(red: 149/255, green: 236/255, blue: 105/255)
private let wechatGreen = Color(red: 7/255, green: 193/255, blue: 96/255)
private let privacyPolicyURL = URL(string: "https://github.com/openonion/whatcha-ios/blob/main/PRIVACY.md")!

struct ChatScreen: View {
    @ObservedObject var model: ChatModel
    let switchRole: () -> Void
    @State private var draft = ""
    @StateObject private var media = ChatMedia()
    @State private var selection: PhotosPickerItem?
    @State private var preview: Data?
    @State private var previewIsDraft = false
    @State private var confirmPairingChange = false
    @State private var slowReply = false
    @FocusState private var typing: Bool
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric private var bodySize: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            if model.needsPairing { unpaired } else { chat }
        }
        .font(.system(size: bodySize))
        .foregroundStyle(Color(red: 17/255, green: 17/255, blue: 17/255))
        .background(chatBackground.ignoresSafeArea())
        .confirmationDialog("重新配对", isPresented: $confirmPairingChange, titleVisibility: .visible) {
            Button("重新配对", role: .destructive) {
                draft = ""
                media.cancelRecording()
                model.beginPairingReplacement()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请孩子发来新口令。新配对成功后，这部手机上的旧聊天会被替换。")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                typing = false
                media.cancelRecording()
            }
        }
        .task(id: scenePhase == .active ? model.childMessagesOrigin : nil) {
            if scenePhase == .active { await model.followChildMessages() }
        }
        .task(id: model.lines.first { $0.delivery == .sent }?.id) {
            slowReply = false
            guard model.lines.contains(where: { $0.delivery == .sent }) else { return }
            do {
                try await Task.sleep(for: .seconds(45))
                slowReply = true
            } catch {}
        }
        .task(id: selection) {
            guard let selection else { return }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self),
                      let jpeg = ChatMedia.photo(data) else { throw CocoaError(.fileReadCorruptFile) }
                try Task.checkCancellation()
                previewIsDraft = true
                preview = jpeg
            } catch is CancellationError {
                return
            } catch {
                media.error = "无法读取这张照片，请重新选择。"
            }
            self.selection = nil
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            NavigationStack {
                Group {
                    if let preview, let image = UIImage(data: preview) {
                        Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("照片预览")
                    }
                }
                .navigationTitle("照片预览")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { preview = nil } }
                    if previewIsDraft {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("发送照片") {
                                if let preview { sendAttachment(.photo(preview)) }
                                preview = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private var unpaired: some View {
        VStack(spacing: 0) {
            if model.status == .refused { statusStrip("口令过期或用过了，\n请孩子重新发一条") }
            if model.status == .offline, let trouble = statusText(model.status) { statusStrip(trouble) }
            pairingPrompt
        }
    }

    private var pairingPrompt: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    Text("请孩子在微信里发来口令，\n长按复制，再回到这里点「粘贴」")
                        .font(.system(size: bodySize, weight: .medium))
                        .lineSpacing(8)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    FamilyPasteControl(identifier: "pairing-paste", onPaste: model.paste, onFailure: model.needsClipboardRetry)
                        .frame(width: 240, height: max(72, bodySize * 3))
                    if model.status == .connecting {
                        ProgressView("正在连接家人…")
                            .font(.callout)
                    } else if model.status == .offline {
                        Button("重新连接") { model.cameBack() }
                            .buttonStyle(.bordered)
                    }
                    if let error = model.pairingError {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.replacingPairing { Button("返回原来的聊天") { model.cancelPairingReplacement() } }
                    Link("隐私政策", destination: privacyPolicyURL)
                        .font(.footnote)
                    Button("选择身份", action: switchRole).font(.footnote)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            Text(model.header)
                .font(.system(size: bodySize, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(.horizontal, 60)
                .padding(.vertical, 4)
                .accessibilityAddTraits(.isHeader)
                .overlay(alignment: .trailing) {
                    Menu {
                        Link("隐私政策", destination: privacyPolicyURL)
                        Button("重新配对") { confirmPairingChange = true }
                        Button("选择身份", action: switchRole)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .frame(width: 60, height: 60)
                    }
                    .accessibilityLabel("关于")
                }
            Divider()
            if let trouble = statusText(model.status) { statusStrip(trouble) }
            if slowReply && model.status == .online {
                Button("等得有点久，检查连接") { model.checkConnection() }
                    .font(.callout)
                    .padding(8)
            }
            if model.lines.isEmpty { emptyChat } else { conversation }
            if showsComposer(model.status) { composer }
        }
    }

    private func statusStrip(_ text: String) -> some View {
        HStack(spacing: 12) {
            RedBang()
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color(red: 253/255, green: 236/255, blue: 236/255))
    }

    private var emptyChat: some View {
        Text(emptyChatHint(model.snapshot.title, status: model.status))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(8)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversation: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(model.lines.enumerated()), id: \.element.id) { index, line in
                            VStack(spacing: 16) {
                                if showsTime(index) { timeLabel(line.at) }
                                MessageRow(line: line, agentName: model.snapshot.title,
                                           retry: { model.retry(line) }, play: {
                                               if case .photo(let data) = line.attachment {
                                                   previewIsDraft = false
                                                   preview = data
                                               } else {
                                                   media.play(line)
                                               }
                                           })
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: model.lines.count) { _, _ in scroll.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: geometry.size.height) { _, _ in scroll.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func showsTime(_ index: Int) -> Bool {
        index == 0 || model.lines[index].at - model.lines[index - 1].at > 300_000
    }

    private func timeLabel(_ at: Int64) -> some View {
        Text(chatTime(at: at))
            .font(.system(size: bodySize * 0.75))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            if let error = media.error {
                Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 12)
            }
            HStack(spacing: 20) {
                if media.recording {
                    Button("取消录音") { media.cancelRecording() }
                    Button("发送语音") {
                        if let attachment = media.finishRecording() { sendAttachment(attachment) }
                    }
                } else {
                    Button { Task { await media.startRecording() } } label: {
                        Label("录音", systemImage: "mic")
                    }
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label("照片", systemImage: "photo")
                    }
                }
                Spacer()
            }
            .font(.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("写消息", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 13)
                    .frame(minHeight: 60)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .focused($typing)
                    .accessibilityLabel("消息")
                    .tint(wechatGreen)
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        model.send(draft)
                        draft = ""
                    } label: {
                        Text("发送")
                            .foregroundStyle(.white)
                            .frame(minWidth: 88, minHeight: 60)
                            .background(wechatGreen, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(barBackground)
    }

    private func sendAttachment(_ attachment: ChatAttachment) {
        model.send(attachment.prompt, attachment: attachment)
    }
}

struct FamilyPasteControl: UIViewRepresentable {
    let identifier: String
    var onPaste: (String) -> Void
    var onFailure: () -> Void

    func makeCoordinator() -> Recipient { Recipient(onPaste: onPaste, onFailure: onFailure) }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .labelOnly
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor(red: 7/255, green: 138/255, blue: 71/255, alpha: 1)
        configuration.baseForegroundColor = .white
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        control.accessibilityIdentifier = identifier
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
        context.coordinator.onFailure = onFailure
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPasteControl, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 240, height: 72))
    }

    final class Recipient: UIResponder {
        var onPaste: (String) -> Void
        var onFailure: () -> Void

        init(onPaste: @escaping (String) -> Void, onFailure: @escaping () -> Void) {
            self.onPaste = onPaste
            self.onFailure = onFailure
            super.init()
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        }

        override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
        }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                DispatchQueue.main.async {
                    if let text = object as? String { self.onPaste(text) }
                    else { self.onFailure() }
                }
            }
        }
    }
}

private struct MessageRow: View {
    let line: Line
    let agentName: String
    let retry: () -> Void
    let play: () -> Void
    @ScaledMetric private var bodySize: CGFloat = 24

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                if line.fromParent { Spacer(minLength: 0) }
                if !line.fromParent { avatar; tail }
                HStack(spacing: 0) {
                    if line.fromParent { deliveryMark }
                    bubble
                        .lineSpacing(bodySize / 6)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("\(sender)：\(line.text)")
                }
                .frame(maxWidth: line.fromParent ? 330 : 270,
                       alignment: line.fromParent ? .trailing : .leading)
                .layoutPriority(-1)
                if line.fromParent { tail; avatar }
                if !line.fromParent { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 12)
            if line.delivery == .failed {
                Text(agentFailed)
                    .font(.system(size: bodySize * 0.75))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    @ViewBuilder private var bubble: some View {
        if case .photo(let data) = line.attachment, let image = UIImage(data: data) {
            Button(action: play) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 230)
            }
            .buttonStyle(.plain).accessibilityHint("查看照片")
        } else if case .voice(_, let seconds) = line.attachment {
            Button(action: play) { Label("\(seconds) 秒", systemImage: "waveform") }
                .buttonStyle(.plain).accessibilityHint("播放或停止语音")
        } else if !line.fromParent {
            Button(action: play) { Text(line.text).multilineTextAlignment(.leading) }
                .buttonStyle(.plain).accessibilityHint("朗读或停止")
        } else {
            Text(line.text)
        }
    }

    private var sender: String {
        if line.fromParent { return "我" }
        return line.childSequence == nil ? "\(agentName)，AI 代答" : "\(agentName)，本人"
    }

    private var bubbleColor: Color {
        if line.fromParent { return parentGreen }
        return line.childSequence == nil
            ? Color(red: 236/255, green: 228/255, blue: 250/255)
            : Color(red: 213/255, green: 235/255, blue: 250/255)
    }

    private var avatar: some View {
        Group {
            if line.fromParent {
                Image("avatar_parent").resizable()
            } else {
                Text(String(agentName.prefix(1)))
                    .font(.system(size: bodySize, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 224/255, green: 236/255, blue: 250/255))
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var tail: some View {
        BubbleTail(pointsLeft: !line.fromParent)
            .fill(bubbleColor)
            .frame(width: 8, height: 16)
            .padding(.top, 22)
            .padding(line.fromParent ? .trailing : .leading, 4)
    }

    private var deliveryMark: some View {
        Group {
            if line.delivery == .failed {
                Button(action: retry) { RedBang().frame(width: 60, height: 60) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("没收到回复，点一下再试")
            } else {
                ZStack {
                    if line.delivery == .queued || line.delivery == .sent {
                        VStack(spacing: 3) {
                            ProgressView().tint(.secondary).accessibilityHidden(true)
                            Text(line.delivery == .queued ? "待发送" : "等回复")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 60, height: 60)
            }
        }
    }
}

@MainActor
private final class ChatMedia: ObservableObject {
    @Published private(set) var recording = false
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var playingID: UUID?
    private var started = Date()
    private var requestingPermission = false

    func startRecording() async {
        guard !recording, !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        error = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "无法录音。请在设置中允许「在干嘛」使用麦克风。"
            return
        }
        stopPlayback()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try session.setActive(true)
            let newRecorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000
            ])
            guard newRecorder.record(forDuration: 30) else { throw CocoaError(.fileWriteUnknown) }
            recorder = newRecorder
            started = Date()
            recording = true
        } catch {
            try? FileManager.default.removeItem(at: url)
            releaseAudioSession()
            self.error = "录音未开始，请重试。"
        }
    }

    func finishRecording() -> ChatAttachment? {
        guard let recorder else { return nil }
        let duration = min(30, Date().timeIntervalSince(started))
        stopRecording()
        defer { try? FileManager.default.removeItem(at: recorder.url) }
        guard duration >= 1, let data = try? Data(contentsOf: recorder.url), !data.isEmpty else {
            error = "录音太短或无法读取，请再录一次。"
            return nil
        }
        return .voice(data, seconds: Int(duration.rounded()))
    }

    func cancelRecording() {
        guard let recorder else { return }
        stopRecording()
        try? FileManager.default.removeItem(at: recorder.url)
    }

    private func stopRecording() {
        recorder?.stop()
        recorder = nil
        recording = false
        releaseAudioSession()
    }

    private func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    func play(_ line: Line) {
        guard !recording else { return }
        let tapStops = playingID == line.id && (synthesizer.isSpeaking || audioPlayer?.isPlaying == true)
        stopPlayback()
        guard !tapStops else { return }
        playingID = line.id
        if case .voice(let data, _) = line.attachment {
            do {
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.play()
            } catch {
                self.error = "无法播放这条语音。"
            }
        } else {
            let utterance = AVSpeechUtterance(string: line.text)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            synthesizer.speak(utterance)
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        playingID = nil
    }

    nonisolated static func photo(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_000
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.7), jpeg.count < 512_000 else {
            return nil
        }
        return jpeg
    }
}

private struct RedBang: View {
    @ScaledMetric private var size: CGFloat = 24
    var body: some View {
        Text("!").font(.system(size: size * 0.75, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(red: 250/255, green: 81/255, blue: 81/255), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct BubbleTail: Shape {
    let pointsLeft: Bool
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: pointsLeft ? rect.maxX : 0, y: 0))
            path.addLine(to: CGPoint(x: pointsLeft ? 0 : rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: pointsLeft ? rect.maxX : 0, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// Same day periods and date wording as Android; local time, milliseconds in history.
private func chatTime(at: Int64) -> String {
    let date = Date(timeIntervalSince1970: Double(at) / 1000)
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: date)
    let part: String
    switch hour {
    case 0...5: part = "凌晨"
    case 6...11: part = "上午"
    case 12: part = "中午"
    case 13...17: part = "下午"
    default: part = "晚上"
    }
    let minute = calendar.component(.minute, from: date)
    let clock = "\(part) \(hour > 12 ? hour - 12 : hour):\(String(format: "%02d", minute))"
    if calendar.isDateInToday(date) { return clock }
    return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日 " + clock
}
