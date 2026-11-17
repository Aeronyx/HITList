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

    // MARK: Round 32 (review 155 finding 5): a crafted ZIP

    /// A ZIP of stored entries, each `(name, data, method)`; `offsets` overrides where each central entry points.
    private func zip(_ entries: [(String, Data, Int)], offsets: [Int]? = nil) -> Data {
        var out = Data()
        var central = Data()
        func u16(_ v: Int, into d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8 & 0xFF)) }
        func u32(_ v: Int, into d: inout Data) { u16(v & 0xFFFF, into: &d); u16(v >> 16 & 0xFFFF, into: &d) }
        var locals: [Int] = []
        for (name, data, method) in entries {
            locals.append(out.count)
            let nameBytes = Data(name.utf8)
            u32(0x0403_4B50, into: &out); u16(20, into: &out); u16(0x800, into: &out); u16(method, into: &out)
            u32(0, into: &out); u32(0, into: &out); u32(data.count, into: &out); u32(data.count, into: &out)
            u16(nameBytes.count, into: &out); u16(0, into: &out)
            out.append(nameBytes); out.append(data)
        }
        for (i, (name, data, method)) in entries.enumerated() {
            let nameBytes = Data(name.utf8)
            u32(0x0201_4B50, into: &central); u16(20, into: &central); u16(20, into: &central); u16(0x800, into: &central)
            u16(method, into: &central); u32(0, into: &central); u32(0, into: &central)
            u32(data.count, into: &central); u32(data.count, into: &central)
            u16(nameBytes.count, into: &central); u16(0, into: &central); u16(0, into: &central)
            u16(0, into: &central); u16(0, into: &central); u32(0, into: &central)
            u32(offsets?[i] ?? locals[i], into: &central)
            central.append(nameBytes)
        }
        let directoryOffset = out.count
        out.append(central)
        u32(0x0605_4B50, into: &out); u16(0, into: &out); u16(0, into: &out)
        u16(entries.count, into: &out); u16(entries.count, into: &out)
        u32(central.count, into: &out); u32(directoryOffset, into: &out); u16(0, into: &out)
        return out
    }

    func testTheHelperMakesAZipTheReaderOpens() throws {
        let entries = try TodoistZip.entries(of: zip([("Home.csv", Data("TYPE,CONTENT\ntask,A\n".utf8), 0)]))
        XCTAssertEqual(entries.map(\.name), ["Home.csv"])
    }

    func testANameThatIsNotACSVIsSkippedBeforeItIsRead() throws {
        // Method 99 would be refused if it were read at all.
        let data = zip([("photo.jpg", Data("not read".utf8), 99), ("Home.csv", Data("TYPE,CONTENT\ntask,A\n".utf8), 0)])
        XCTAssertEqual(try TodoistZip.entries(of: data).map(\.name), ["Home.csv"])
    }

    func testTheInflatedTotalIsCapped() {
        let csv = Data(repeating: 0x41, count: 40)
        let data = zip([("a.csv", csv, 0), ("b.csv", csv, 0), ("c.csv", csv, 0)])
        XCTAssertThrowsError(try TodoistZip.entries(of: data, maxTotal: 100)) { error in
            XCTAssertEqual(error as? TodoistZip.ZipError, .tooLarge)
        }
        XCTAssertEqual(try TodoistZip.entries(of: data, maxTotal: 120).count, 3)
    }

    func testAnOffsetAlreadySeenIsRefused() {
        let csv = Data("TYPE,CONTENT\ntask,A\n".utf8)
        let data = zip([("a.csv", csv, 0), ("a.csv", csv, 0)], offsets: [0, 0])
        XCTAssertThrowsError(try TodoistZip.entries(of: data)) { error in
            XCTAssertEqual(error as? TodoistZip.ZipError, .damaged)
        }
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
