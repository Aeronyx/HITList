import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 64: Shared Tasks is one forced Group. Its screen is a Group's screen (a section per set of people when there
/// is more than one), Sharing… holds the sets, and it is last under Groups everywhere. In-memory stores only.
@MainActor
final class SharedGroupTests: XCTestCase {
    private let me = "_me000000000000000000000000000000"
    private let sam = "_sam00000000000000000000000000000"

    private func person(_ name: String, me: Bool = false, owner: Bool = false, pending: Bool = false) -> SharedPerson {
        SharedPerson(id: name, name: name, avatar: nil, isOwner: owner, isMe: me, isPending: pending, memberID: name)
    }

    // MARK: - The Group's place

    func testTheGroupIsAGroupToEveryScreenWithItsOwnID() {
        XCTAssertEqual(SidebarItem.sharedTasks, .project(SharedTasksGroup.id))
        XCTAssertNotEqual(SidebarItem.sharedTasks, .settings)
        XCTAssertNil(ShellPlace.tab(for: .sharedTasks), "it is pushed from Browse, as a Group is")
        var place = ShellPlace(tab: .today)
        place.select(.sharedTasks)
        XCTAssertEqual(place.list, .sharedTasks)
    }

    // MARK: - Sets of people

    func testASetIsNamedByItsPeoplesFirstNames() {
        XCTAssertEqual(SharedSets.names([]), "Only you")
        XCTAssertEqual(SharedSets.names([person("Sam Rivera")]), "Sam")
        XCTAssertEqual(SharedSets.names([person("Sam Rivera"), person("Alex Kim")]), "Sam & Alex")
        XCTAssertEqual(SharedSets.names([person("Sam"), person("Alex"), person("Kim Lee")]), "Sam, Alex & Kim")
        XCTAssertEqual(SharedSets.names([person("sam@example.com")]), "sam@example.com", "an address stays whole")
    }

    func testASetsHeadingIsItsNamesAndCountAsOneRun() {
        let heading = SharedSetHeading(people: [person("Sam Rivera"), person("Alex Kim")], count: 3)
        XCTAssertEqual(String(heading.label.characters), "Sam & Alex · 3")
        XCTAssertEqual(heading.accessibilityLabel, "Shared with Sam Rivera and Alex Kim, 3 tasks")
        XCTAssertEqual(String(SharedSetHeading(people: [], count: 0).label.characters), "Only you")
    }

    private func store() -> SharedTasksStore {
        let store = SharedTasksStore(persistence: .memory)
        store.setMe(me)
        return store
    }

    /// A list Sam owns and shared with me, as fetched.
    private func samsList(_ title: String, in store: SharedTasksStore) -> UUID {
        let id = UUID()
        let t = SharedClock.stamp(Date())
        store.applyServerList(SharedListFields(title: Stamped(title, at: t), colorHex: Stamped("#4FD1E8", at: t), createdAt: t),
                              systemFields: nil, listID: id, scope: .joined, ownerName: sam)
        store.applyShare(SharedShareInfo(participants: [
            SharedParticipant(userID: sam, name: "Sam Rivera", contact: nil, role: .owner, status: .accepted, canWrite: true, isCurrentUser: false),
            SharedParticipant(userID: me, name: "George", contact: nil, role: .participant, status: .accepted, canWrite: true, isCurrentUser: true),
        ], url: nil, archive: nil), listID: id, scope: .joined, ownerName: sam)
        return id
    }

    func testTheSetsAreInTheirPeoplesOrderTheOnesNobodyJoinedLast() throws {
        let store = store()
        let mine = try store.createList(title: "Shared Tasks")
        let sams = samsList("Groceries", in: store)
        let order = SharedSets.ordered(store.lists, me: me).map(\.id)
        XCTAssertEqual(order, [sams, mine.id])
        XCTAssertEqual(SharedPeople.others(in: try XCTUnwrap(store.list(sams)), me: me).map(\.name), ["Sam Rivera"])
        XCTAssertTrue(SharedPeople.others(in: mine, me: me).isEmpty)
    }

    // MARK: - Sharing… with nothing shared yet

    func testTheFirstInviteMakesTheSetItShares() {
        let invite = SharedListInvite(listID: nil, title: SharedTasksGroup.name, existing: nil)
        XCTAssertNil(invite.listID, "no set yet: one is made when the share sheet asks for its share")
        XCTAssertEqual(invite.title, "Shared Tasks")
    }
}
