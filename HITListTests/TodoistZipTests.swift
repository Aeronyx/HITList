import XCTest
@testable import HITList
import HITListCore

/// Brief 137: a Todoist backup is one ZIP with a CSV per project; it is read without asking anyone to unzip it.
final class TodoistZipTests: XCTestCase {
    /// Made by Python's zipfile: "Work [2301234567].csv" deflated, "Inbox [1].csv" stored (with a BOM), and a
    /// Finder "__MACOSX/._Work.csv" that is not a project.
    static let backup = Data(base64Encoded: """
    UEsDBBQAAAAIAAAAIQAv/PCaTQAAAAsDAAAVAAAAV29yayBbMjMwMTIzNDU2N10uY3N2C4kMcNVx9vcLcfUL0QkI8vQP8gyJ5OUqSSzO1gnOyCxQyCzRMYTy\
    3TJzclKLFHIy81IVSvIVkvNzC4pSi4sVylNzcnRMRhWNKhrSigBQSwMEFAAAAAAAAAAhALcKwpwgAAAAIAAAAA0AAABJbmJveCBbMV0uY3N277u/VFlQRSxD\
    T05URU5UDQp0YXNrLENhbGwgbXVtDQpQSwMEFAAAAAAAAAAhADmc+wYEAAAABAAAABMAAABfX01BQ09TWC8uX1dvcmsuY3N2anVua1BLAQIUAxQAAAAIAAAA\
    IQAv/PCaTQAAAAsDAAAVAAAAAAAAAAAAAACAAQAAAABXb3JrIFsyMzAxMjM0NTY3XS5jc3ZQSwECFAMUAAAAAAAAACEAtwrCnCAAAAAgAAAADQAAAAAAAAAA\
    AAAAgAGAAAAASW5ib3ggWzFdLmNzdlBLAQIUAxQAAAAAAAAAIQA5nPsGBAAAAAQAAAATAAAAAAAAAAAAAACAAcsAAABfX01BQ09TWC8uX1dvcmsuY3N2UEsF\
    BgAAAAADAAMAvwAAAAABAAAAAA==
    """)!

    func testStoredAndDeflatedEntries() throws {
        let entries = try TodoistZip.entries(of: Self.backup)
        XCTAssertEqual(entries.map(\.name), ["Work [2301234567].csv", "Inbox [1].csv", "__MACOSX/._Work.csv"])
        let work = String(decoding: entries[0].data, as: UTF8.self)
        XCTAssertTrue(work.hasPrefix("TYPE,CONTENT,PRIORITY\r\ntask,Ship it,1\r\n"))
        XCTAssertEqual(work.components(separatedBy: "Filler").count, 21)
        XCTAssertEqual(entries[2].data, Data("junk".utf8))
    }

    func testABackupBecomesItsProjects() throws {
        let projects = try TodoistFiles.projects(from: [.init(name: "todoist-backup.zip", data: Self.backup)])
        XCTAssertEqual(projects.map(\.name), ["Work", "Inbox"], "Finder's __MACOSX files are not projects")
        XCTAssertEqual(projects.map(\.taskCount), [21, 1])
    }

    func testOneOrSeveralCSVs() throws {
        let csv = Data("TYPE,CONTENT\ntask,Water plants\n".utf8)
        let projects = try TodoistFiles.projects(from: [.init(name: "Garden.csv", data: csv), .init(name: "Home [9].csv", data: csv)])
        XCTAssertEqual(projects.map(\.name), ["Garden", "Home"])
    }

    func testAnythingElseIsRefusedInPlainWords() {
        XCTAssertThrowsError(try TodoistZip.entries(of: Data("not a zip".utf8)))
        XCTAssertThrowsError(try TodoistFiles.projects(from: [.init(name: "notes.txt", data: Data("hello".utf8))])) { error in
            XCTAssertEqual(error as? TodoistFiles.FileError, .notTodoist("notes.txt"))
            XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                           "notes.txt is not a file from Todoist. Choose a backup (.zip) or a project's CSV.")
        }
        var truncated = Self.backup
        truncated.removeLast(30)
        XCTAssertThrowsError(try TodoistZip.entries(of: truncated))
    }
}
