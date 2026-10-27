import Foundation
import XCTest
@testable import HITListCore

final class SeedIdentityTests: XCTestCase {
    func testMatchesRFC4122Version5Vector() {
        // uuid5(NAMESPACE_DNS, "python.org") from Python's uuid module.
        let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        XCTAssertEqual(SeedIdentity.uuid(for: "python.org", in: dns).uuidString, "886313E1-3B8A-5372-9B90-0C9AEE199E5D")
    }

    func testStableAcrossRuns() {
        // Pinned value: if this changes, already-seeded records in CloudKit would no longer match.
        XCTAssertEqual(SeedIdentity.savedFilter("focus").uuidString, "723A2095-77CE-5C6C-8027-CF898D9C8ED3")
        XCTAssertEqual(SeedIdentity.savedFilter("this-week").uuidString, "5202621E-8C76-58ED-BB75-ED51D6EB4E11")
        XCTAssertEqual(SeedIdentity.savedFilter("waiting").uuidString, "AC83C050-9EDD-5ED1-A884-492675D49EC8")
        XCTAssertEqual(SeedIdentity.savedFilter("unscheduled").uuidString, "3643596D-7011-5892-B671-5D343442E795")
        XCTAssertEqual(SeedIdentity.namespace.uuidString, "6B1F3E2A-9C4D-4E5F-8A7B-1D2C3E4F5A6B")
    }

    func testDistinctAcrossNames() {
        let keys = ["focus", "this-week", "waiting", "unscheduled"]
        let ids = Set(keys.map(SeedIdentity.savedFilter))
        XCTAssertEqual(ids.count, keys.count)
        XCTAssertNotEqual(SeedIdentity.uuid(for: "a"), SeedIdentity.uuid(for: "A"))
    }

    func testIsVersion5RFC4122() {
        let id = SeedIdentity.savedFilter("focus").uuid
        XCTAssertEqual(id.6 >> 4, 5)
        XCTAssertEqual(id.8 >> 6, 0b10)
    }
}
