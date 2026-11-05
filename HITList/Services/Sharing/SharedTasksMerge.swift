import Foundation

/// How two copies of the same record become one (brief 51): last writer wins per field. Pure, so every device
/// that sees the same two copies picks the same result, in either order.
///
/// - Each field carries the time it was last set (`Stamped`); the later one wins, compared in whole milliseconds.
///   On a tie the larger value (by its JSON encoding) wins, so the result never depends on which copy was local.
/// - The completion (done or not, who, when) is one unit, never mixed from two copies. When both copies are
///   completed, the earlier completion is kept: "completed by Sam at 10:02" stays Sam's even if someone else's
///   device ticked it again before it saw Sam's. Otherwise (one open, one done) the later change wins.
/// - Values that never change (`createdAt`, who created it) come from the server copy; so do the system fields,
///   since the next save must carry the server's change tag.
enum SharedTasksMerge {
    static func pick<Value>(_ a: Stamped<Value>, _ b: Stamped<Value>) -> Stamped<Value> {
        let ma = SharedClock.millis(a.changedAt), mb = SharedClock.millis(b.changedAt)
        if ma != mb { return ma > mb ? a : b }
        if a.value == b.value { return a }
        return tieKey(a.value) >= tieKey(b.value) ? a : b
    }

    static func completion(_ a: Stamped<SharedCompletion?>, _ b: Stamped<SharedCompletion?>) -> Stamped<SharedCompletion?> {
        if let ca = a.value, let cb = b.value {
            let ma = SharedClock.millis(ca.at), mb = SharedClock.millis(cb.at)
            if ma != mb { return ma < mb ? a : b }
            if ca.by != cb.by { return ca.by < cb.by ? a : b }
            return pick(a, b)
        }
        return pick(a, b)
    }

    static func task(local: SharedTask, server: SharedTask) -> SharedTask {
        var merged = server
        merged.title = pick(local.title, server.title)
        merged.notes = pick(local.notes, server.notes)
        merged.priority = pick(local.priority, server.priority)
        merged.due = pick(local.due, server.due)
        merged.completion = completion(local.completion, server.completion)
        return merged
    }

    static func member(local: SharedMember, server: SharedMember) -> SharedMember {
        var merged = server
        merged.name = pick(local.name, server.name)
        merged.avatar = pick(local.avatar, server.avatar)
        return merged
    }

    static func list(local: SharedListFields, server: SharedListFields) -> SharedListFields {
        var merged = server
        merged.title = pick(local.title, server.title)
        merged.colorHex = pick(local.colorHex, server.colorHex)
        return merged
    }

    /// Whether `merged` holds anything the server copy doesn't, so it has to be saved again.
    static func differs(_ merged: SharedTask, from server: SharedTask) -> Bool {
        !same(merged.title, server.title) || !same(merged.notes, server.notes) || !same(merged.priority, server.priority)
            || !same(merged.due, server.due) || !same(merged.completion, server.completion)
    }

    static func differs(_ merged: SharedMember, from server: SharedMember) -> Bool {
        !same(merged.name, server.name) || !same(merged.avatar, server.avatar)
    }

    static func differs(_ merged: SharedListFields, from server: SharedListFields) -> Bool {
        !same(merged.title, server.title) || !same(merged.colorHex, server.colorHex)
    }

    /// Equal values set at the same millisecond.
    static func same<Value>(_ a: Stamped<Value>, _ b: Stamped<Value>) -> Bool {
        a.value == b.value && SharedClock.millis(a.changedAt) == SharedClock.millis(b.changedAt)
    }

    /// A stable order between two different values: their JSON with sorted keys.
    private static func tieKey<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode([value])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
