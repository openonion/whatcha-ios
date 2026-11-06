import SwiftUI
import WhatchaCore

private let chatBackground = Color(red: 237/255, green: 237/255, blue: 237/255)
private let barBackground = Color(red: 247/255, green: 247/255, blue: 247/255)
private let parentGreen = Color(red: 149/255, green: 236/255, blue: 105/255)
private let wechatGreen = Color(red: 7/255, green: 193/255, blue: 96/255)

struct ChatScreen: View {
    @ObservedObject var model: ChatModel
    @State private var draft = ""
    @FocusState private var typing: Bool
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric private var bodySize: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            Text(model.header)
                .font(.system(size: bodySize, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
                .accessibilityAddTraits(.isHeader)
            Divider()
            if let trouble = statusText(model.status) { statusStrip(trouble) }
            if model.lines.isEmpty { emptyChat } else { conversation }
            if model.status != .unpaired { composer }
        }
        .font(.system(size: bodySize))
        .foregroundStyle(Color(red: 17/255, green: 17/255, blue: 17/255))
        .background(chatBackground.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { typing = false }
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
        Text(model.status == .unpaired ? "给孩子打个电话" :
             "想知道孩子在干嘛，\n就在下面问\(model.snapshot.title)，\n打字就行")
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
                                MessageRow(line: line, agentName: model.snapshot.title) { model.retry(line) }
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
            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: $draft, axis: .vertical)
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
}

private struct MessageRow: View {
    let line: Line
    let agentName: String
    let retry: () -> Void
    @ScaledMetric private var bodySize: CGFloat = 24

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                if line.fromParent { Spacer(minLength: 0) }
                if !line.fromParent { avatar; tail }
                HStack(spacing: 0) {
                    if line.fromParent { deliveryMark }
                    Text(line.text)
                        .lineSpacing(bodySize / 6)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(line.fromParent ? parentGreen : .white,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("\(line.fromParent ? "我" : agentName)：\(line.text)")
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

    private var avatar: some View {
        Image(line.fromParent ? "avatar_parent" : "avatar_agent")
            .resizable()
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }

    private var tail: some View {
        BubbleTail(pointsLeft: !line.fromParent)
            .fill(line.fromParent ? parentGreen : .white)
            .frame(width: 8, height: 16)
            .padding(.top, 22)
            .padding(line.fromParent ? .trailing : .leading, 4)
    }

    private var deliveryMark: some View {
        Group {
            if line.delivery == .failed {
                Button(action: retry) { RedBang().frame(width: 60, height: 60) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("没发出去，点一下再发一次")
            } else {
                ZStack {
                    if line.delivery == .queued || line.delivery == .sent {
                        ProgressView().tint(.secondary).accessibilityLabel("正在发送")
                    }
                }
                .frame(width: 60, height: 60)
            }
        }
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
