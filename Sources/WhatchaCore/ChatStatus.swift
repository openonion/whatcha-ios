public enum Status: CaseIterable { case unpaired, connecting, online, offline, refused }

public let connectDeadline: Double = 10
public func nextDelay(_ previous: Double) -> Double { min(previous * 2, 60) }
public func retryNow(_ status: Status, waiting: Bool) -> Bool { waiting && status != .online && status != .refused }
public func shownOnReturn(_ status: Status) -> Status { status == .offline ? .connecting : status }
public func giveUpTry(_ status: Status) -> Bool { status != .online }

public func headerTitle(_ name: String, lines: [Line], status: Status) -> String {
    if status == .online && lines.contains(where: { $0.delivery == .sent }) { return "对方正在输入..." }
    return status == .connecting ? "\(name)(连接中…)" : name
}

public func statusText(_ status: Status) -> String? {
    switch status {
    case .unpaired, .refused: return "还没连上，\n请让孩子帮忙看看"
    case .offline: return "暂时联系不上，\n稍后会自己重试"
    case .connecting, .online: return nil
    }
}

public func showsComposer(_ status: Status) -> Bool { status != .unpaired && status != .refused }

public func emptyChatHint(_ name: String, status: Status) -> String {
    showsComposer(status) ? "想知道孩子在干嘛，\n就在下面问\(name)，\n打字就行" : "还没连上，\n请让孩子帮忙看看"
}
