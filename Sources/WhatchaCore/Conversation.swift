import Foundation

public enum Delivery: String, Codable { case queued, sent, done, failed }

public struct Line: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var fromParent: Bool
    public var text: String
    public var at: Int64
    public var delivery: Delivery = .done
    public var childSequence: Int64?

    public init(fromParent: Bool, text: String, at: Int64, delivery: Delivery = .done) {
        self.fromParent = fromParent
        self.text = text
        self.at = at
        self.delivery = delivery
    }
}

public struct ChildMessage: Decodable, Equatable, Identifiable {
    public let id: UUID
    public let sequence: Int64
    public let text: String
    public let at: Int64
}

public struct ChildMessagePage: Decodable {
    public let messages: [ChildMessage]
}

public struct HistoryItem: Equatable {
    public var fromParent: Bool
    public var text: String
    public init(_ fromParent: Bool, _ text: String) {
        self.fromParent = fromParent
        self.text = text
    }
}

public let agentFailed = "这条消息暂时没收到回复。点一下红色的感叹号，再发一次。"

// The host accepts one INPUT per turn; replies have no message ID.
public extension Array where Element == Line {
    var childCursor: Int64 { compactMap(\.childSequence).max() ?? 0 }

    func addingChildMessages(_ messages: [ChildMessage]) -> [Line] {
        var cursor = childCursor
        var combined = self
        for message in messages.sorted(by: { $0.sequence < $1.sequence }) where message.sequence > cursor {
            var line = Line(fromParent: false, text: message.text, at: message.at)
            line.id = message.id
            line.childSequence = message.sequence
            let index = combined.lastIndex(where: { $0.at <= message.at }).map { $0 + 1 } ?? 0
            combined.insert(line, at: index)
            cursor = message.sequence
        }
        return combined
    }

    func nextToSend() -> Line? {
        contains { $0.delivery == .sent } ? nil : first { $0.delivery == .queued }
    }

    func answerOldest() -> [Line] {
        guard let line = first(where: { $0.delivery == .sent }) else { return self }
        return changing(line, to: .done)
    }

    func requeueSent() -> [Line] {
        map { line in
            var next = line
            if next.delivery == .sent { next.delivery = .queued }
            return next
        }
    }

    func markSent(_ line: Line) -> [Line] { changing(line, to: .sent) }

    func failOldest(_ message: String) -> [Line] {
        guard !message.isEmpty, let line = first(where: { $0.delivery == .sent }) else { return self }
        return changing(line, to: .failed)
    }

    func retry(_ line: Line) -> [Line] {
        line.delivery == .failed ? changing(line, to: .queued) : self
    }

    func afterReconnect(agentRunning: Bool, history: [HistoryItem], now: Int64) -> [Line] {
        if agentRunning { return self }
        guard let answer = answerIn(history) else { return requeueSent() }
        return answerOldest() + [Line(fromParent: false, text: answer, at: now)]
    }

    private func answerIn(_ history: [HistoryItem]) -> String? {
        guard let waiting = first(where: { $0.delivery == .sent }),
              let asked = history.lastIndex(where: { $0.fromParent }),
              history[asked].text == waiting.text,
              let answer = history.dropFirst(asked + 1).last?.text else { return nil }
        if answer == last(where: { !$0.fromParent && $0.childSequence == nil })?.text {
            // Equal reply text does not identify a turn: the demo and real agents
            // can answer multiple questions identically. Require a newer question
            // occurrence before recovering an otherwise indistinguishable reply.
            let remoteQuestions = history.filter { $0.fromParent && $0.text == waiting.text }.count
            let completedQuestions = filter {
                $0.fromParent && $0.delivery == .done && $0.text == waiting.text
            }.count
            guard remoteQuestions > completedQuestions else { return nil }
        }
        return answer
    }

    private func changing(_ selected: Line, to delivery: Delivery) -> [Line] {
        map { line in
            var next = line
            if next.id == selected.id { next.delivery = delivery }
            return next
        }
    }
}
