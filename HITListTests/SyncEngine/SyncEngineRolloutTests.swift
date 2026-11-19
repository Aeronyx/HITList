import XCTest
import CloudKit
@testable import HITList

/// Brief 170: the word that lets every device move (`SyncEngineRollout`). Every mapping from the record (or the
/// error) to the answer, the build comparison at its edges, one log line per answer and no retry, and that a release
/// build has no road that writes the record. Nothing here talks to iCloud: the fetch is a stand-in.
final class SyncEngineRolloutTests: XCTestCase {
    typealias Rollout = SyncEngineRollout
    typealias Fields = SyncEngineRollout.Fields

    // MARK: - The record

    func testTheRecordIsEveryoneInThePublicDefaultZone() {
        XCTAssertEqual(Rollout.recordType, "HLRollout")
        XCTAssertEqual(Rollout.recordName, "everyone")
        XCTAssertEqual(Rollout.recordID.recordName, "everyone")
        XCTAssertEqual(Rollout.recordID.zoneID, CKRecordZone.default().zoneID)
        XCTAssertEqual(Rollout.minBuildField, "minBuild")
        XCTAssertEqual(Rollout.pausedField, "paused")
    }

    // MARK: - Fields to answer

    func testNoRecordIsNotYet() {
        XCTAssertEqual(Rollout.answer(fields: nil, build: "52"), .notYet)
    }

    func testARecordWithNeitherFieldLetsEveryBuildGo() {
        XCTAssertEqual(Rollout.answer(fields: Fields(), build: "52"), .go)
        XCTAssertEqual(Rollout.answer(fields: Fields(), build: "1"), .go)
        // No minimum: a build whose number cannot be read goes too (nothing to compare).
        XCTAssertEqual(Rollout.answer(fields: Fields(), build: "abc"), .go)
    }

    func testPausedIsPausedWhateverTheMinimum() {
        XCTAssertEqual(Rollout.answer(fields: Fields(paused: 1), build: "52"), .paused)
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 50, paused: 1), build: "52"), .paused)
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 99, paused: 1), build: "52"), .paused)
        // Anything but 0 waits: the safe side for a value typed by hand.
        XCTAssertEqual(Rollout.answer(fields: Fields(paused: 2), build: "52"), .paused)
        XCTAssertEqual(Rollout.answer(fields: Fields(paused: -1), build: "52"), .paused)
    }

    func testPausedZeroIsNotPaused() {
        XCTAssertEqual(Rollout.answer(fields: Fields(paused: 0), build: "52"), .go)
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 52, paused: 0), build: "52"), .go)
    }

    func testTheBuildComparisonAtItsEdges() {
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 52), build: "52"), .go, "at the minimum moves")
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 52), build: "53"), .go, "above it moves")
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 52), build: "51"), .notYet, "one below waits")
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 0), build: "0"), .go)
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: -5), build: "1"), .go)
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 100), build: "99"), .notYet, "compared as numbers")
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 9), build: "10"), .go, "compared as numbers, not text")
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: Int64.max), build: "52"), .notYet)
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: Int64.max), build: "\(Int64.max)"), .go)
    }

    func testABuildNumberThatCannotBeReadWaitsForAMinimum() {
        for build in ["", "abc", "52a", "5.2", "99999999999999999999"] {
            XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 1), build: build), .notYet, build)
        }
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 52), build: " 52 "), .go, "spaces around are read")
    }

    func testAnUnreadableFieldIsUnknown() {
        XCTAssertEqual(Rollout.answer(fields: Fields(unreadable: true), build: "52"), .unknown)
        XCTAssertEqual(Rollout.answer(fields: Fields(minBuild: 1, paused: 0, unreadable: true), build: "52"), .unknown)
    }

    // MARK: - CloudKit's record read

    func testFieldsAreReadFromARecord() {
        let record = CKRecord(recordType: Rollout.recordType, recordID: Rollout.recordID)
        XCTAssertEqual(Fields(record: record), Fields(), "an empty record: neither field")
        record[Rollout.minBuildField] = 52 as Int64
        XCTAssertEqual(Fields(record: record), Fields(minBuild: 52))
        record[Rollout.pausedField] = 1 as Int64
        XCTAssertEqual(Fields(record: record), Fields(minBuild: 52, paused: 1))
        record[Rollout.minBuildField] = nil
        XCTAssertEqual(Fields(record: record), Fields(paused: 1))
    }

    func testAFieldOfTheWrongKindIsUnreadable() {
        let text = CKRecord(recordType: Rollout.recordType, recordID: Rollout.recordID)
        text[Rollout.minBuildField] = "52" as NSString
        XCTAssertTrue(Fields(record: text).unreadable)
        let double = CKRecord(recordType: Rollout.recordType, recordID: Rollout.recordID)
        double[Rollout.pausedField] = 0.5 as Double
        XCTAssertTrue(Fields(record: double).unreadable)
        XCTAssertEqual(Rollout.answer(fields: Fields(record: double), build: "52"), .unknown)
    }

    // MARK: - Errors to answer

    func testNoSuchRecordIsNotYet() {
        XCTAssertEqual(Rollout.answer(error: CKError(.unknownItem)), .notYet)
        XCTAssertEqual(Rollout.answer(error: NSError(domain: CKErrorDomain, code: CKError.Code.unknownItem.rawValue)), .notYet)
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [Rollout.recordID: CKError(.unknownItem)]])
        XCTAssertEqual(Rollout.answer(error: partial), .notYet)
    }

    func testEveryOtherErrorIsUnknown() {
        let codes: [CKError.Code] = [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
                                     .zoneBusy, .notAuthenticated, .permissionFailure, .badContainer,
                                     .missingEntitlement, .serverRejectedRequest, .internalError, .zoneNotFound,
                                     .accountTemporarilyUnavailable, .operationCancelled, .incompatibleVersion]
        for code in codes {
            XCTAssertEqual(Rollout.answer(error: CKError(code)), .unknown, "\(code.rawValue)")
        }
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [Rollout.recordID: CKError(.networkFailure)]])
        XCTAssertEqual(Rollout.answer(error: partial), .unknown)
        XCTAssertEqual(Rollout.answer(error: URLError(.timedOut)), .unknown)
        XCTAssertEqual(Rollout.answer(error: CancellationError()), .unknown)
    }

    // MARK: - The asker: one fetch, one line, never throws

    private final class Box: @unchecked Sendable {
        var fetches = 0
        var lines: [String] = []
    }

    private func ask(build: String = "52", _ result: Result<Fields?, Error>) async -> (Rollout.Answer, Box) {
        let box = Box()
        let asker = SyncEngineRolloutAsker(build: build, fetch: {
            box.fetches += 1
            return try result.get()
        }, log: { box.lines.append($0) })
        let answer = await asker.answer()
        return (answer, box)
    }

    func testTheAskerMapsEachCaseWithOneFetchAndOneLine() async {
        let cases: [(Result<Fields?, Error>, Rollout.Answer, String)] = [
            (.success(Fields()), .go, "yes (build 52, every build)"),
            (.success(Fields(minBuild: 50)), .go, "yes (build 52, from build 50)"),
            (.success(Fields(minBuild: 53)), .notYet, "not yet (from build 53, this is build 52)"),
            (.success(Fields(paused: 1)), .paused, "paused, waiting"),
            (.success(nil), .notYet, "not yet (no word)"),
            (.failure(CKError(.unknownItem)), .notYet, "not yet (no word)"),
            (.failure(CKError(.networkUnavailable)), .unknown, "couldn't tell (network unavailable)"),
            (.failure(CKError(.requestRateLimited)), .unknown, "couldn't tell (iCloud is busy, will retry)"),
            (.failure(CKError(.permissionFailure)), .unknown, "couldn't tell (app can't use iCloud)"),
            (.success(Fields(unreadable: true)), .unknown, "couldn't tell (the word holds something unreadable)"),
        ]
        for (result, expected, words) in cases {
            let (answer, box) = await ask(result)
            XCTAssertEqual(answer, expected, words)
            XCTAssertEqual(box.fetches, 1, "one fetch, no retry: \(words)")
            XCTAssertEqual(box.lines, ["Asked iCloud whether this device may move to the new sync: \(words)"])
        }
    }

    func testTheAskerAsksAgainOnlyWhenAskedAgain() async {
        let box = Box()
        let asker = SyncEngineRolloutAsker(build: "52", fetch: {
            box.fetches += 1
            throw CKError(.networkUnavailable)
        }, log: { box.lines.append($0) })
        _ = await asker.answer()
        XCTAssertEqual(box.fetches, 1)
        _ = await asker.answer()
        XCTAssertEqual(box.fetches, 2)
        XCTAssertEqual(box.lines.count, 2)
    }

    func testTheCloudKitAskerIsBuiltForThisBuildAndTheEnginesContainer() {
        // Built, never asked: nothing here reaches iCloud.
        _ = CloudKitRollout(log: { _ in })
        XCTAssertFalse(AppInfo.build.isEmpty)
        XCTAssertEqual(SyncEngineSwitch.containerID, "iCloud.com.trammells.hitlist.sync")
    }

    // MARK: - No released road writes the word

    /// Every source file of every target, with the `#if DEBUG` parts taken out: nothing touches a public database but
    /// `SyncEngineRollout.swift`, and that file holds no save, modify or delete, and nothing kept on disk.
    func testTheReleaseBuildHasNoPathThatWritesTheRecord() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let folders = ["HITList", "HITListWidgets", "HITListShare", "HITListMCP"]
        var files: [URL] = []
        for folder in folders {
            guard let walker = FileManager.default.enumerator(at: root.appending(path: folder), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" { files.append(url) }
        }
        guard files.count > 50 else { throw XCTSkip("the sources are out of this process's reach") }

        let publicDatabase = ["publicCloudDatabase", "database(with: .public)", "databaseScope: .public", "Scope.public",
                              "scope: .public"]
        let writes = ["save(", "modifyRecords", "CKModifyRecordsOperation", "deleteRecord", "CKRecord(recordType",
                      "UserDefaults", "FileManager", "write(to"]
        var sawDebugHook = false
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let release = Self.releaseOnly(text)
            if file.lastPathComponent == "SyncEngineRehearsal.swift" {
                sawDebugHook = text.contains("publicCloudDatabase") && text.contains("database.save(")
                XCTAssertFalse(release.contains("publicCloudDatabase"), "the rehearsal's hook is Debug only")
            }
            if file.lastPathComponent == "SyncEngineRollout.swift" {
                for word in writes { XCTAssertFalse(release.contains(word), "SyncEngineRollout.swift: \(word)") }
                continue
            }
            for word in publicDatabase {
                XCTAssertFalse(release.contains(word), "\(file.lastPathComponent) reaches a public database: \(word)")
            }
            XCTAssertFalse(release.contains("CKRecord(recordType: SyncEngineRollout"), file.lastPathComponent)
        }
        XCTAssertTrue(sawDebugHook, "the grep found the Debug hook that writes the record (or it reads nothing)")
    }

    /// The text a release build compiles: `#if DEBUG` regions out (their `#else` kept), everything else kept.
    static func releaseOnly(_ text: String) -> String {
        var stack: [Bool] = [] // true: this level's current branch is Debug only
        var kept: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") {
                stack.append(trimmed == "#if DEBUG")
                continue
            }
            if trimmed.hasPrefix("#elseif") || trimmed == "#else" {
                if let last = stack.popLast() { stack.append(last ? false : trimmed == "#elseif DEBUG") }
                continue
            }
            if trimmed.hasPrefix("#endif") {
                _ = stack.popLast()
                continue
            }
            if !stack.contains(true) { kept.append(line) }
        }
        return kept.joined(separator: "\n")
    }

    func testTheReleaseFilterDropsDebugRegions() {
        let text = "a\n#if DEBUG\nb\n#else\nc\n#endif\n#if os(iOS)\nd\n#if DEBUG\ne\n#endif\n#endif\nf"
        XCTAssertEqual(Self.releaseOnly(text), "a\nc\nd\nf")
    }

    /// Several records (one made in the Console under a name of its own beside `everyone`, or two by mistake): one
    /// that says wait wins over every other, whichever was changed last, because the pause is the brake; otherwise
    /// the one changed last is the word (brief 172: a go named `everyone` used to beat a newer pause).
    func testAmongSeveralRecordsAPauseWinsThenTheNewest() {
        typealias Fields = SyncEngineRollout.Fields
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func at(_ days: Double) -> Date { t0.addingTimeInterval(days * 86_400) }
        XCTAssertNil(SyncEngineRollout.word(among: []))
        XCTAssertEqual(SyncEngineRollout.word(among: [(Fields(), at(0))]), Fields())
        // A newer pause beside an older go.
        XCTAssertEqual(SyncEngineRollout.word(among: [(Fields(), at(0)), (Fields(paused: 1), at(1))]), Fields(paused: 1))
        // An older pause beside a newer go: still paused, until that record is changed or deleted.
        XCTAssertEqual(SyncEngineRollout.word(among: [(Fields(paused: 1), at(0)), (Fields(), at(1))]), Fields(paused: 1))
        // A record that cannot be read is no yes either.
        XCTAssertEqual(SyncEngineRollout.answer(fields: SyncEngineRollout.word(among: [(Fields(unreadable: true), at(0)), (Fields(), at(1))]),
                                                build: "40"), .unknown)
        // No pause: the one changed last, with its own minimum.
        XCTAssertEqual(SyncEngineRollout.word(among: [(Fields(minBuild: 30), at(0)), (Fields(minBuild: 50), at(2)), (Fields(), at(1))]),
                       Fields(minBuild: 50))
        // "paused 0" is not a pause.
        XCTAssertEqual(SyncEngineRollout.word(among: [(Fields(paused: 0), at(0)), (Fields(minBuild: 9), at(1))]), Fields(minBuild: 9))
    }
}
