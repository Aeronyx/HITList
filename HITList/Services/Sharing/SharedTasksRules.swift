import Foundation

/// Who may do what in a shared list (brief 51). CloudKit enforces the same on the server: a participant with
/// "can make changes" may write any record in the list's zone but can't change the share; only the owner can.
enum SharedTasksPermissions {
    enum Action: CaseIterable {
        case addTask, editTask, completeTask, deleteTask
        case renameList, invite, removeMember, stopSharing, deleteList
        case leave
    }

    enum Role: Equatable { case owner, participant }

    static func role(in list: SharedList) -> Role { list.isOwned ? .owner : .participant }

    /// Whether this account may write to `list`: always for the owner; for a participant, what their share says
    /// (yes until the share has been fetched, since lists are only ever shared as "can make changes").
    static func canWrite(in list: SharedList) -> Bool {
        list.isOwned || (list.share?.currentUser?.canWrite ?? true)
    }

    static func allows(_ action: Action, role: Role, canWrite: Bool) -> Bool {
        switch action {
        case .addTask, .editTask, .completeTask, .deleteTask:
            return role == .owner || canWrite
        case .renameList, .invite, .removeMember, .stopSharing, .deleteList:
            return role == .owner
        case .leave:
            return role == .participant
        }
    }

    static func allows(_ action: Action, in list: SharedList) -> Bool {
        allows(action, role: role(in: list), canWrite: canWrite(in: list))
    }
}

/// A person as the Shared screens show them.
struct SharedPerson: Identifiable, Equatable {
    var id: String
    var name: String
    var avatar: Data?
    var isOwner: Bool
    var isMe: Bool
    var isPending: Bool
    /// Their user record name, for removing them; nil for an invitation not accepted yet.
    var memberID: SharedMemberID?
    /// The address an invitation went to (owner's view), for withdrawing one nobody accepted.
    var contact: String? = nil

    /// The name to draw initials from: none for "You" or "Someone", which get the plain person symbol.
    var avatarName: String { name == SharedPeople.you || name == SharedPeople.someone ? "" : name }
}

/// Names and faces: a member's HITList profile where they copied one in (`SharedMember`), else the name iCloud
/// sharing gives, else the address the invitation went to.
enum SharedPeople {
    static let someone = "Someone"
    /// Me, before I have a HITList name and before iCloud gives one.
    static let you = "You"

    /// Owner first, then me, then the others who joined (by name), then invitations not accepted yet.
    static func people(in list: SharedList, me: SharedMemberID?) -> [SharedPerson] {
        var people: [SharedPerson] = []
        var seen = Set<String>()

        func add(memberID: SharedMemberID?, participant: SharedParticipant?, isOwner: Bool) {
            let isMe = participant?.isCurrentUser == true || (memberID != nil && memberID == me)
            let resolvedID = isMe ? (me ?? memberID) : memberID
            let key = resolvedID ?? participant?.contact ?? participant?.name ?? UUID().uuidString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            let member = list.member(resolvedID)
            let profileName = member.map(\.name.value).flatMap(nonEmpty)
            let name = profileName ?? participant?.name.flatMap(nonEmpty) ?? participant?.contact.flatMap(nonEmpty) ?? (isMe ? you : someone)
            people.append(SharedPerson(id: key, name: name, avatar: member?.avatar.value, isOwner: isOwner, isMe: isMe,
                                       isPending: participant?.status == .pending, memberID: resolvedID,
                                       contact: participant?.contact))
        }

        let participants = list.share?.participants ?? []
        // The owner: from the share when there is one; for my own unshared list, me.
        if let owner = participants.first(where: { $0.role == .owner }) {
            add(memberID: owner.isCurrentUser ? me : owner.userID, participant: owner, isOwner: true)
        } else if list.isOwned {
            add(memberID: me, participant: nil, isOwner: true)
        } else {
            add(memberID: list.ownerName, participant: nil, isOwner: true)
        }
        let guests = participants.filter { $0.role != .owner && $0.status != .removed }
        let meFirst = guests.filter(\.isCurrentUser)
        let accepted = guests.filter { !$0.isCurrentUser && $0.status == .accepted }
        let pending = guests.filter { !$0.isCurrentUser && $0.status != .accepted }
        for p in meFirst { add(memberID: me, participant: p, isOwner: false) }
        let named = accepted.map { p in (p, list.member(p.userID).map(\.name.value).flatMap(nonEmpty) ?? p.name ?? "") }
        for (p, _) in named.sorted(by: { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }) {
            add(memberID: p.userID, participant: p, isOwner: false)
        }
        // Members who wrote a record but aren't on the share as fetched (the share not fetched yet).
        if list.share == nil || participants.isEmpty {
            for member in list.members.sorted(by: { $0.name.value < $1.name.value }) {
                add(memberID: member.id, participant: nil, isOwner: false)
            }
        }
        for p in pending { add(memberID: p.userID, participant: p, isOwner: false) }
        return people
    }

    /// Everyone in the list but me (brief 64: the people a shared task is shared with, where its labels would be). A list
    /// I own has me as its owner, so its owner is left out too, whether or not `me` is known yet.
    static func others(in list: SharedList, me: SharedMemberID?) -> [SharedPerson] {
        people(in: list, me: me).filter { !$0.isMe && !(list.isOwned && $0.isOwner) }
    }

    /// "you", "Sam", or the name kept with the completion.
    static func name(of memberID: SharedMemberID, in list: SharedList, me: SharedMemberID?, fallback: String?) -> String {
        if memberID == me { return "you" }
        if let name = list.member(memberID).map(\.name.value).flatMap(nonEmpty) { return name }
        if let participant = list.share?.participants.first(where: { $0.userID == memberID }), let name = participant.name.flatMap(nonEmpty) {
            return name
        }
        return fallback.flatMap(nonEmpty) ?? someone
    }

    /// "Completed by Sam"; nil for an open task.
    static func completedBy(_ task: SharedTask, in list: SharedList, me: SharedMemberID?) -> String? {
        guard let completion = task.completion.value else { return nil }
        return "Completed by \(name(of: completion.by, in: list, me: me, fallback: completion.byName))"
    }

    private static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// The order of a shared list's tasks: open ones by priority, then due (undated last), then when they were added;
/// completed ones after them, most recently completed first.
enum SharedTaskOrdering {
    static func sorted(_ tasks: [SharedTask]) -> [SharedTask] {
        let open = tasks.filter { !$0.isCompleted }.sorted { a, b in
            if a.priority.value != b.priority.value { return a.priority.value < b.priority.value }
            switch (a.due.value?.date, b.due.value?.date) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
        let done = tasks.filter(\.isCompleted).sorted { a, b in
            let x = a.completion.value?.at ?? .distantPast, y = b.completion.value?.at ?? .distantPast
            return x != y ? x > y : a.id.uuidString < b.id.uuidString
        }
        return open + done
    }
}
