public enum Status: CaseIterable { case unpaired, connecting, online, offline }

public let connectDeadline: Double = 10
public func nextDelay(_ previous: Double) -> Double { min(previous * 2, 60) }
public func retryNow(_ status: Status, waiting: Bool) -> Bool { waiting && status != .online }
public func shownOnReturn(_ status: Status) -> Status { status == .offline ? .connecting : status }
public func giveUpTry(_ status: Status) -> Bool { status != .online }

public func headerTitle(_ name: String, lines: [Line], status: Status) -> String {
    if status == .online && lines.contains(where: { $0.delivery == .sent }) { return "对方正在输入..." }
    return status == .connecting ? "\(name)(连接中…)" : name
}

public func statusText(_ status: Status) -> String? {
    switch status {
    case .unpaired: return "还没连上，\n让孩子重发安装包"
    case .offline: return "暂时联系不上，\n稍后会自己重试"
    case .connecting, .online: return nil
    }
}
