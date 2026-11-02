import XCTest
import CloudKit
@testable import HITList

/// The sync log (brief 25, item 1): a bounded JSON-lines file, newest kept, read back in order, exported
/// as text; and the wording of durations, errors and saves.
final class SyncLogTests: XCTestCase {
    private var directory: URL!
    /// 2026-11-02 17:17:49.677 UTC, a whole number of milliseconds so it survives the round trip exactly.
    private let start = Date(timeIntervalSince1970: 1_793_639_869.677)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "SyncLogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var url: URL { directory.appending(path: "SyncLog/sync-log.jsonl") }

    /// A log whose clock advances one second per entry from `start`.
    private func makeLog(maxEntries: Int = SyncLog.defaultMaxEntries, maxBytes: Int = SyncLog.defaultMaxBytes) -> SyncLog {
        let ticks = Counter()
        let start = self.start
        return SyncLog(url: url, maxEntries: maxEntries, maxBytes: maxBytes, mirrorToOSLog: false) {
            start.addingTimeInterval(TimeInterval(ticks.next()))
        }
    }

    // MARK: Round trip and order

    func testRoundTripKeepsEveryField() {
        let log = makeLog()
        let written = log.record(.event, "export failed after 1.2 s: network unavailable", level: .error,
                                 fields: ["error": "CKErrorDomain 3", "retryAfter": "5.0 s"])
        let read = log.entries()
        XCTAssertEqual(read, [written])
        XCTAssertEqual(read.first?.date, start)
        XCTAssertEqual(read.first?.kind, .event)
        XCTAssertEqual(read.first?.level, .error)
        XCTAssertEqual(read.first?.fields["retryAfter"], "5.0 s")
        XCTAssertEqual(read.first?.pid, ProcessInfo.processInfo.processIdentifier)
    }

    func testEntriesComeBackInTheOrderTheyWereRecorded() {
        let log = makeLog()
        for i in 1...5 { log.record(.note, "line \(i)") }
        let read = log.entries()
        XCTAssertEqual(read.map(\.message), (1...5).map { "line \($0)" })
        XCTAssertEqual(read.map(\.seq), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(read.map(\.id)).count, 5, "ids are unique")
    }

    func testAnExplicitDateIsKept() {
        let log = makeLog()
        let earlier = start.addingTimeInterval(-30)
        log.record(.save, "3 local saves: 3 updated", date: earlier)
        XCTAssertEqual(log.entries().first?.date, earlier)
    }

    func testEmptyFieldsAreLeftOutOfTheFile() throws {
        let log = makeLog()
        log.record(.scene, "App active")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("\"f\""), text)
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    // MARK: Bounds

    func testTheOldestLinesAreDroppedPastTheEntryCap() {
        let log = makeLog(maxEntries: 40)
        for i in 1...100 { log.record(.note, "line \(i)") }
        let read = log.entries()
        XCTAssertLessThanOrEqual(read.count, 40)
        XCTAssertGreaterThanOrEqual(read.count, 30, "a trim keeps three quarters of the cap")
        XCTAssertEqual(read.last?.message, "line 100", "the newest line is always kept")
        let numbers = read.compactMap { Int($0.message.dropFirst(5)) }
        XCTAssertEqual(numbers, Array((101 - numbers.count)...100), "what is kept is the newest run, without gaps")
    }

    func testTheFileStaysUnderTheByteCap() {
        let log = makeLog(maxBytes: 4096)
        let padding = String(repeating: "x", count: 80)
        for i in 1...200 {
            log.record(.note, "line \(i) \(padding)")
            XCTAssertLessThanOrEqual(log.byteCount(), 4096, "a line that crosses the cap is trimmed in the same call")
        }
        XCTAssertEqual(log.entries().last?.message, "line 200 \(padding)")
    }

    func testLinesThatDontDecodeAreSkipped() throws {
        let log = makeLog()
        log.record(.note, "first")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"torn\": \n".utf8))
        try handle.close()
        log.record(.note, "second")
        XCTAssertEqual(log.entries().map(\.message), ["first", "second"])
    }

    func testAKindFromANewerBuildReadsAsANote() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"k":"telepathy","l":"loud","m":"from the future","n":1,"p":7,"t":1793639869677}"#
        try Data((line + "\n").utf8).write(to: url)
        let read = makeLog().entries()
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first?.kind, .note)
        XCTAssertEqual(read.first?.level, .info)
        XCTAssertEqual(read.first?.pid, 7)
    }

    func testTwoWritersOnOneFileKeepEveryLine() {
        // Two app instances share the file; each appends whole lines, and a trim by one doesn't lose the other's.
        let a = makeLog(maxEntries: 40), b = makeLog(maxEntries: 40)
        for i in 1...30 {
            a.record(.note, "a\(i)")
            b.record(.note, "b\(i)")
        }
        let read = a.entries()
        XCTAssertLessThanOrEqual(read.count, 40)
        XCTAssertEqual(read.last?.message, "b30")
        XCTAssertEqual(read.dropLast().last?.message, "a30")
        XCTAssertEqual(read.map(\.message), b.entries().map(\.message))
    }

    func testANilURLKeepsNothing() {
        let log = SyncLog(url: nil, mirrorToOSLog: false)
        log.record(.note, "nowhere")
        XCTAssertEqual(log.entries(), [])
        XCTAssertEqual(log.byteCount(), 0)
    }

    func testEachRecordIsPostedOnTheMainQueue() {
        let posted = expectation(forNotification: .syncLogDidRecord, object: nil) { note in
            XCTAssertTrue(Thread.isMainThread)
            return SyncLog.entry(from: note)?.message == "posted"
        }
        makeLog().record(.note, "posted")
        wait(for: [posted], timeout: 2)
    }

    func testTheSharedLogLivesInTheAppGroupAndDevelopmentRunsGetTheirOwn() throws {
        let base = try XCTUnwrap(SyncLog.defaultURL(suffix: nil))
        XCTAssertEqual(base.lastPathComponent, "sync-log.jsonl")
        XCTAssertEqual(base.deletingLastPathComponent().lastPathComponent, "SyncLog")
        XCTAssertEqual(SyncLog.defaultURL(suffix: "s25")?.lastPathComponent, "sync-log-s25.jsonl")
        XCTAssertEqual(SyncLog.defaultURL(suffix: "")?.lastPathComponent, "sync-log.jsonl")
        XCTAssertNil(SyncLog.shared.url, "unit tests never write the real log")
    }

    // MARK: Text

    func testTextExportIsOneLinePerEntryOldestFirst() {
        let log = makeLog()
        log.record(.launch, "Launch HITList 0.3.4 (11) · macOS · Production · TestFlight", level: .notice, fields: ["pid": "52543"])
        log.record(.event, "export failed after 1.2 s: network unavailable", level: .error,
                   fields: ["error": "CKErrorDomain 3", "ckError": "networkUnavailable"])
        let text = SyncLog.text(log.entries(), header: ["HITList sync log"], timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(text, """
            HITList sync log
            Times are local (UTC+00:00), oldest first; 2 entries.

            2026-11-02 17:17:49.677  launch    Launch HITList 0.3.4 (11) · macOS · Production · TestFlight · pid=52543
            2026-11-02 17:17:50.677  event     ERROR export failed after 1.2 s: network unavailable · ckError=networkUnavailable · error=CKErrorDomain 3

            """)
    }

    func testTheTextNamesTheOffsetOfTheTimeZone() {
        let text = SyncLog.text([], timeZone: TimeZone(secondsFromGMT: -6 * 3600)!)
        XCTAssertTrue(text.hasPrefix("Times are local (UTC-06:00), oldest first; 0 entries."), text)
    }

    func testOSLogLinesCarryTheKindAndFields() {
        let entry = SyncLogEntry(seq: 1, date: start, pid: 1, kind: .event, level: .info, message: "import finished in 0.49 s",
                                 fields: ["id": "3F2A9C1B", "duration": "0.49 s"])
        XCTAssertEqual(SyncLog.osLogText(entry), "[event] import finished in 0.49 s · duration=0.49 s · id=3F2A9C1B")
    }

    // MARK: Wording

    func testDurations() {
        let d = SyncLogFormat.duration
        XCTAssertEqual(d(0.494), "0.49 s")
        XCTAssertEqual(d(-1), "0.00 s")
        XCTAssertEqual(d(4.26), "4.3 s")
        XCTAssertEqual(d(12.4), "12 s")
        XCTAssertEqual(d(420), "7 min")
        XCTAssertEqual(d(432), "7 min 12 s")
        XCTAssertEqual(d(7200), "2 h")
        XCTAssertEqual(d(7380), "2 h 3 min")
        XCTAssertEqual(d(273_600), "3 d 4 h")
    }

    func testErrorFieldsKeepEverythingTheErrorSays() {
        let underlying = CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 30])
        let error = NSError(domain: NSCocoaErrorDomain, code: 134_410, userInfo: [
            NSLocalizedDescriptionKey: "CloudKit integration failed",
            NSUnderlyingErrorKey: underlying as NSError,
            "NSDebugDescription": "line one\nline two",
        ])
        let fields = SyncLogFormat.errorFields(error)
        XCTAssertEqual(fields["error"], "NSCocoaErrorDomain 134410")
        XCTAssertEqual(fields["description"], "CloudKit integration failed")
        XCTAssertNil(fields["ckError"], "not a CloudKit error itself")
        XCTAssertEqual(fields["retryAfter"], "30 s", "taken from the underlying CKError")
        XCTAssertTrue(fields["underlying"]?.hasPrefix("CKErrorDomain 7 requestRateLimited") == true, fields["underlying"] ?? "")
        XCTAssertEqual(fields["info.NSDebugDescription"], "line one line two")
    }

    func testErrorFieldsNameCloudKitCodesAndPartialFailures() {
        let partial = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: ["CD_TaskItem/1": CKError(.quotaExceeded), "CD_TaskItem/2": CKError(.quotaExceeded)],
            CKErrorRetryAfterKey: 5,
        ])
        let fields = SyncLogFormat.errorFields(partial)
        XCTAssertEqual(fields["error"], "CKErrorDomain 2")
        XCTAssertEqual(fields["ckError"], "partialFailure")
        XCTAssertEqual(fields["retryAfter"], "5.0 s")
        XCTAssertEqual(fields["partialErrors"], "2: CD_TaskItem/1: CKErrorDomain quotaExceeded; CD_TaskItem/2: CKErrorDomain quotaExceeded")
    }

    func testLongValuesAreClipped() {
        XCTAssertEqual(SyncLogFormat.clip("abcdef", 4), "abc…")
        XCTAssertEqual(SyncLogFormat.clip("abc", 4), "abc")
    }

    @MainActor
    func testSaveSummaryWording() {
        var summary = CloudSyncMonitor.SaveSummary(inserted: 1, updated: 2, entities: ["TaskItem": 2, "Project": 1])
        XCTAssertEqual(summary.text, "1 inserted, 2 updated")
        XCTAssertEqual(summary.entityText, "TaskItem 2, Project 1")
        summary.add(CloudSyncMonitor.SaveSummary(deleted: 1, entities: ["Project": 1]))
        XCTAssertEqual(summary.text, "1 inserted, 2 updated, 1 deleted")
        XCTAssertEqual(summary.entityText, "Project 2, TaskItem 2")
        XCTAssertEqual(CloudSyncMonitor.SaveSummary(userInfo: nil).total, 0)
    }
}

/// What the push log line says about a remote notification (brief 25, item 2).
final class SyncPushTests: XCTestCase {
    /// The shape CloudKit sends for a database subscription such as NSPersistentCloudKitContainer's.
    private let databasePush: [AnyHashable: Any] = [
        "aps": ["content-available": 1],
        "ck": [
            "ce": 2,
            "cid": "iCloud.com.trammells.hitlist",
            "nid": "6c3f0a2e-1b4d-4c55-9a8e-1f2e3d4c5b6a",
            "met": ["dbs": 1, "sid": "com.apple.coredata.cloudkit.private.subscription",
                    "zid": "com.apple.coredata.cloudkit.zone", "zoid": "_defaultOwner"],
        ] as [String: Any],
    ]

    func testACloudKitDatabasePushIsDescribed() {
        let push = SyncPush(userInfo: databasePush)
        XCTAssertTrue(push.isCloudKit)
        XCTAssertEqual(push.container, "iCloud.com.trammells.hitlist")
        XCTAssertEqual(push.subscriptionID, "com.apple.coredata.cloudkit.private.subscription")
        XCTAssertEqual(push.environmentCode, "2")
        XCTAssertEqual(push.fields["ce"], "2")
        XCTAssertEqual(push.fields["nid"], "6c3f0a2e-1b4", "the notification id is shortened")
        XCTAssertEqual(push.fields["cloudKit"], "yes")
        XCTAssertTrue(push.summary.hasPrefix("CloudKit "), push.summary)
        XCTAssertTrue(push.summary.hasSuffix("iCloud.com.trammells.hitlist"), push.summary)
    }

    func testAPushThatIsntCloudKitsSaysSo() {
        let push = SyncPush(userInfo: ["aps": ["alert": "Hello"]])
        XCTAssertFalse(push.isCloudKit)
        XCTAssertEqual(push.summary, "not from CloudKit")
        XCTAssertEqual(push.fields, ["cloudKit": "no"])
    }

    func testScopeNames() {
        XCTAssertEqual(SyncPush.scopeName(rawValue: 1), "public")
        XCTAssertEqual(SyncPush.scopeName(rawValue: 2), "private")
        XCTAssertEqual(SyncPush.scopeName(rawValue: 3), "shared")
        XCTAssertNil(SyncPush.scopeName(rawValue: 99))
    }
}

/// Which CloudKit environment and channel a build reports (brief 25, item 4), from sample entitlements,
/// provisioning profiles and receipts.
final class SyncEnvironmentTests: XCTestCase {
    func testEntitlementValues() {
        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: "Production"), .production)
        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: "Development"), .development)
        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: ["Production"]), .production)
        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: ["Production", "Development"]), .unknown,
                       "a profile that allows both doesn't say which the binary uses")
        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: nil), .unknown)
        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: "Staging"), .unknown)
    }

    /// An `embedded.mobileprovision`: a CMS envelope (binary) around an XML property list.
    private func profile(getTaskAllow: Bool, environments: [String], aps: String) -> Data {
        let list = environments.map { "<string>\($0)</string>" }.joined()
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>Name</key><string>HITList profile</string>
            <key>Entitlements</key><dict>
            <key>aps-environment</key><string>\(aps)</string>
            <key>com.apple.developer.icloud-container-environment</key><array>\(list)</array>
            <key>get-task-allow</key>\(getTaskAllow ? "<true/>" : "<false/>")
            </dict></dict></plist>
            """
        return Data([0x30, 0x82, 0x2E, 0x4B, 0x06, 0x09, 0x2A, 0x86]) + Data(xml.utf8) + Data([0xA0, 0x82, 0x0B, 0x00])
    }

    func testAProvisioningProfileIsCutOutOfItsEnvelope() throws {
        let parsed = try XCTUnwrap(ProvisioningProfile.parse(profile(getTaskAllow: true, environments: ["Development"], aps: "development")))
        XCTAssertEqual(parsed.name, "HITList profile")
        XCTAssertTrue(parsed.getTaskAllow)
        XCTAssertEqual(parsed.entitlements["aps-environment"] as? String, "development")
        XCTAssertNil(ProvisioningProfile.parse(Data("not a profile".utf8)))
    }

    func testIOSBuildsResolveToTheirEnvironment() {
        XCTAssertTrue(SyncEnvironment.resolveIOS(profile: nil, hasProfile: false) == (.production, "production"),
                      "TestFlight and App Store builds carry no profile")
        let development = ProvisioningProfile.parse(profile(getTaskAllow: true, environments: ["Development", "Production"], aps: "development"))
        XCTAssertTrue(SyncEnvironment.resolveIOS(profile: development, hasProfile: true) == (.development, "development"))
        // The profile inside release.sh's exported .ipa (checked 2026-11-02): both environments, no get-task-allow.
        let distribution = ProvisioningProfile.parse(profile(getTaskAllow: false, environments: ["Production", "Development"], aps: "production"))
        XCTAssertTrue(SyncEnvironment.resolveIOS(profile: distribution, hasProfile: true) == (.production, "production"))
        let single = ProvisioningProfile.parse(profile(getTaskAllow: false, environments: ["Production"], aps: "production"))
        XCTAssertTrue(SyncEnvironment.resolveIOS(profile: single, hasProfile: true) == (.production, "production"))
        XCTAssertTrue(SyncEnvironment.resolveIOS(profile: nil, hasProfile: true) == (.unknown, nil), "a profile that won't parse")
    }

    func testReceiptsTellTestFlightFromTheAppStore() throws {
        XCTAssertEqual(SyncEnvironment.receiptKind(url: nil), .none)
        XCTAssertEqual(SyncEnvironment.receiptKind(url: URL(filePath: "/nowhere/StoreKit/sandboxReceipt")), .sandbox,
                       "iOS names a TestFlight receipt; the file needn't exist yet")
        XCTAssertEqual(SyncEnvironment.receiptKind(url: URL(filePath: "/nowhere/_MASReceipt/receipt")), .none)
        XCTAssertEqual(SyncEnvironment.receiptKind(contents: Data("\u{0C}\u{11}ProductionSandbox\u{02}".utf8)), .sandbox)
        XCTAssertEqual(SyncEnvironment.receiptKind(contents: Data("\u{0C}\u{0A}Production\u{02}".utf8)), .production)
    }

    func testChannels() {
        XCTAssertEqual(SyncEnvironment.channel(isDebug: true, hasProfile: true, receipt: .none), .debug)
        XCTAssertEqual(SyncEnvironment.channel(isDebug: false, hasProfile: false, receipt: .sandbox), .testFlight)
        XCTAssertEqual(SyncEnvironment.channel(isDebug: false, hasProfile: false, receipt: .production), .appStore)
        XCTAssertEqual(SyncEnvironment.channel(isDebug: false, hasProfile: true, receipt: .production), .xcode)
        XCTAssertEqual(SyncEnvironment.channel(isDebug: false, hasProfile: true, receipt: .none), .xcode)
        XCTAssertEqual(SyncEnvironment.channel(isDebug: false, hasProfile: false, receipt: .none), .unknown)
    }

    func testSummaryAndExplanation() {
        let testFlight = SyncEnvironment(cloudKit: .production, push: "production", channel: .testFlight, build: "11")
        XCTAssertEqual(testFlight.summary, "Production · TestFlight build 11")
        XCTAssertFalse(testFlight.isDevelopment)
        XCTAssertEqual(SyncEnvironment.explanation,
                       "A Mac run from Xcode syncs with Development; TestFlight builds sync with Production, so the two don't see each other.")
    }

    /// What `codesign -d --entitlements :-` printed on 2026-11-02 for the installed TestFlight Mac app, a
    /// Debug Mac build and the iOS app exported by release.sh, read the way SecTask hands values over.
    func testEntitlementPlistsOfRealBuilds() throws {
        func entitlements(_ xml: String) throws -> [String: Any] {
            try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any])
        }
        let head = #"<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>"#
        let containers = "<key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.com.trammells.hitlist</string></array><key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>"
        let macTestFlight = try entitlements(head + "<key>beta-reports-active</key><true/><key>com.apple.application-identifier</key><string>UC8N98H3RT.com.trammells.hitlist</string><key>com.apple.developer.aps-environment</key><string>production</string><key>com.apple.developer.icloud-container-environment</key><string>Production</string>" + containers + "<key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.application-groups</key><array><string>UC8N98H3RT.com.trammells.hitlist</string></array></dict></plist>")
        let macDebug = try entitlements(head + "<key>com.apple.application-identifier</key><string>UC8N98H3RT.com.trammells.hitlist</string><key>com.apple.developer.aps-environment</key><string>development</string><key>com.apple.developer.icloud-container-environment</key><string>Development</string>" + containers + "<key>com.apple.security.get-task-allow</key><true/></dict></plist>")
        let iOSExport = try entitlements(head + "<key>application-identifier</key><string>UC8N98H3RT.com.trammells.hitlist</string><key>aps-environment</key><string>production</string><key>beta-reports-active</key><true/><key>com.apple.developer.icloud-container-environment</key><string>Production</string>" + containers + "<key>get-task-allow</key><false/></dict></plist>")

        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: macTestFlight[SyncEnvironment.cloudKitEnvironmentKey]), .production)
        XCTAssertEqual(macTestFlight[SyncEnvironment.macPushKey] as? String, "production")
        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: macDebug[SyncEnvironment.cloudKitEnvironmentKey]), .development)
        XCTAssertEqual(macDebug[SyncEnvironment.macPushKey] as? String, "development")
        XCTAssertEqual(SyncEnvironment.cloudKitEnvironment(from: iOSExport[SyncEnvironment.cloudKitEnvironmentKey]), .production)
        XCTAssertEqual(iOSExport[SyncEnvironment.iOSPushKey] as? String, "production")
        XCTAssertNil(iOSExport["com.apple.developer.icloud-container-development-container-identifiers"],
                     "App Store Connect rejects builds that carry it")
    }

    func testThisTestBuildIsADebugBuild() {
        XCTAssertEqual(SyncEnvironment.current.channel, .debug)
        XCTAssertEqual(SyncEnvironment.current.build, AppInfo.build)
        // Unsigned (CI) builds carry no entitlements to read.
        if ProcessInfo.processInfo.environment["HITLIST_UNSIGNED"] == nil {
            XCTAssertEqual(SyncEnvironment.current.cloudKit, .development)
            XCTAssertEqual(SyncEnvironment.current.push, "development")
        }
    }

    // MARK: - Every channel, from the entitlements each build carries (beta review)

    /// What `codesign -d --entitlements :-` printed on 2026-11-02 (`testEntitlementPlistsOfRealBuilds`),
    /// reduced to the keys detection reads, plus Xcode's iOS development signing.
    private enum Signed {
        static let macTestFlight: [String: Any] = [
            "beta-reports-active": true, "com.apple.developer.aps-environment": "production",
            "com.apple.developer.icloud-container-environment": "Production"]
        static let macDevelopment: [String: Any] = [
            "com.apple.developer.aps-environment": "development",
            "com.apple.developer.icloud-container-environment": "Development", "com.apple.security.get-task-allow": true]
        static let iOSExport: [String: Any] = [
            "aps-environment": "production", "beta-reports-active": true,
            "com.apple.developer.icloud-container-environment": "Production", "get-task-allow": false]
        static let iOSDevelopment: [String: Any] = [
            "aps-environment": "development",
            "com.apple.developer.icloud-container-environment": "Development", "get-task-allow": true]
    }

    private func resolve(_ platform: SyncEnvironment.Platform, debug: Bool = false, signed: [String: Any]?,
                         profile: Bool, parsed: ProvisioningProfile? = nil, receipt: SyncEnvironment.Receipt) -> SyncEnvironment {
        SyncEnvironment.resolve(.init(platform: platform, isDebugBuild: debug, entitlements: signed, hasProfile: profile,
                                      profile: parsed, receipt: receipt), build: "13")
    }

    private func assert(_ env: SyncEnvironment, _ cloudKit: SyncEnvironment.CloudKit, _ channel: SyncEnvironment.Channel,
                        push: String?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(env.cloudKit, cloudKit, message, file: file, line: line)
        XCTAssertEqual(env.channel, channel, message, file: file, line: line)
        XCTAssertEqual(env.push, push, message, file: file, line: line)
    }

    func testEveryMacChannel() {
        assert(resolve(.macOS, debug: true, signed: Signed.macDevelopment, profile: true, receipt: .none),
               .development, .debug, push: "development", "Debug run from Xcode")
        assert(resolve(.macOS, signed: Signed.macDevelopment, profile: true, receipt: .none),
               .development, .xcode, push: "development", "Release build signed for development, copied out of DerivedData")
        assert(resolve(.macOS, signed: Signed.macTestFlight, profile: true, receipt: .sandbox),
               .production, .testFlight, push: "production", "TestFlight")
        assert(resolve(.macOS, signed: Signed.macTestFlight, profile: true, receipt: .none),
               .production, .testFlight, push: "production", "TestFlight before its receipt is there (Mac apps keep a profile)")
        assert(resolve(.macOS, signed: Signed.macTestFlight, profile: true, receipt: .production),
               .production, .appStore, push: "production", "Mac App Store")
        assert(resolve(.macOS, debug: true, signed: nil, profile: false, receipt: .none),
               .unknown, .debug, push: nil, "unsigned (CI): nothing to read, so nothing is isolated")
    }

    func testEveryIOSChannel() {
        assert(resolve(.iOSDevice, debug: true, signed: Signed.iOSDevelopment, profile: true, receipt: .none),
               .development, .debug, push: "development", "Debug run on the phone from Xcode")
        assert(resolve(.iOSDevice, signed: Signed.iOSExport, profile: false, receipt: .sandbox),
               .production, .testFlight, push: "production", "TestFlight")
        assert(resolve(.iOSDevice, signed: Signed.iOSExport, profile: false, receipt: .production),
               .production, .appStore, push: "production", "App Store")
        assert(resolve(.iOSSimulator, debug: true, signed: nil, profile: false, receipt: .none),
               .development, .debug, push: "development", "simulator, signature not readable")
        assert(resolve(.iOSSimulator, debug: true, signed: Signed.iOSDevelopment, profile: false, receipt: .none),
               .development, .debug, push: "development", "simulator with its simulated entitlements")
    }

    func testAnUnreadableSignatureFallsBackToTheProfileAndTheReceipt() {
        let development = ProvisioningProfile.parse(profile(getTaskAllow: true, environments: ["Development", "Production"], aps: "development"))
        assert(resolve(.iOSDevice, debug: true, signed: nil, profile: true, parsed: development, receipt: .none),
               .development, .debug, push: "development", "a development profile")
        assert(resolve(.iOSDevice, signed: nil, profile: false, receipt: .sandbox),
               .production, .testFlight, push: "production", "no profile and a TestFlight receipt")
    }

    /// The rule brief 26 asked for: a TestFlight or App Store build is never Development, whatever else
    /// says so, because Development opens HITList-Development.store, empty, and looks like data loss.
    func testATestFlightBuildIsNeverDevelopment() {
        assert(resolve(.macOS, signed: Signed.macDevelopment, profile: true, receipt: .sandbox),
               .production, .testFlight, push: "development", "a TestFlight receipt, whatever the entitlements claim")
        var exported = Signed.macDevelopment
        exported["beta-reports-active"] = true
        XCTAssertEqual(resolve(.macOS, signed: exported, profile: true, receipt: .none).cloudKit, .production,
                       "exported for App Store Connect")
        let development = ProvisioningProfile.parse(profile(getTaskAllow: true, environments: ["Development", "Production"], aps: "development"))
        assert(resolve(.iOSDevice, signed: nil, profile: true, parsed: development, receipt: .sandbox),
               .production, .testFlight, push: "development", "a TestFlight receipt beats a development profile")
        // Every TestFlight install (sandbox receipt), whatever its signature says or whether it can be read,
        // and every App Store install (production receipt on an exported build, or no profile at all).
        let anySignature: [[String: Any]?] = [Signed.macTestFlight, Signed.iOSExport, Signed.macDevelopment, Signed.iOSDevelopment, nil]
        for platform in [SyncEnvironment.Platform.macOS, .iOSDevice] {
            for signed in anySignature {
                let testFlight = resolve(platform, signed: signed, profile: platform == .macOS, receipt: .sandbox)
                XCTAssertEqual(testFlight.channel, .testFlight, "\(platform)")
                XCTAssertEqual(testFlight.cloudKit, .production, "\(platform) \(String(describing: signed))")
                XCTAssertNil(SyncStoreGuard.isolationSuffix(environment: testFlight, processEnvironment: [:]))
            }
            for signed in [Signed.macTestFlight, Signed.iOSExport] {
                let appStore = resolve(platform, signed: signed, profile: platform == .macOS, receipt: .production)
                XCTAssertEqual(appStore.channel, .appStore, "\(platform)")
                XCTAssertEqual(appStore.cloudKit, .production, "\(platform)")
            }
        }
        XCTAssertEqual(resolve(.iOSDevice, signed: nil, profile: false, receipt: .production).cloudKit, .production,
                       "an iOS App Store install whose signature can't be read")
    }

    /// The store guard's own lock: even an environment that says Development keeps the real store when
    /// its channel is TestFlight or the App Store.
    func testTheStoreGuardNeverIsolatesADistributionBuild() {
        for channel in [SyncEnvironment.Channel.testFlight, .appStore] {
            let env = SyncEnvironment(cloudKit: .development, push: "development", channel: channel, build: "13")
            XCTAssertNil(SyncStoreGuard.isolationSuffix(environment: env, processEnvironment: [:]), channel.rawValue)
        }
    }

    // MARK: Reading a binary's own entitlements

    private func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }

    /// A minimal 64-bit Mach-O: header, one LC_CODE_SIGNATURE, and a super blob holding an entitlements
    /// blob (after a code directory slot, as real signatures have).
    private func machO(entitlements xml: String?) -> Data {
        var blob = Data()
        if let xml {
            let body = Data(xml.utf8)
            let directory = be32(0xFADE_0C02) + be32(12) + be32(0)
            let entitlements = be32(0xFADE_7171) + be32(UInt32(8 + body.count)) + body
            let header = 12 + 2 * 8
            blob = be32(0xFADE_0CC0) + be32(UInt32(header + directory.count + entitlements.count)) + be32(2)
                + be32(0) + be32(UInt32(header)) + be32(5) + be32(UInt32(header + directory.count))
                + directory + entitlements
        }
        let signatureOffset: UInt32 = 32 + 16
        var data = le32(0xFEED_FACF) + le32(0x0100_000C) + le32(0) + le32(2) + le32(1) + le32(16) + le32(0) + le32(0)
        data += le32(0x1D) + le32(16) + le32(signatureOffset) + le32(UInt32(blob.count))
        return data + blob
    }

    private let sampleEntitlements = #"<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>beta-reports-active</key><true/><key>com.apple.developer.icloud-container-environment</key><string>Production</string><key>aps-environment</key><string>production</string></dict></plist>"#

    func testTheEntitlementsAreReadFromTheCodeSignature() throws {
        let read = try XCTUnwrap(CodeSignature.entitlements(inExecutable: machO(entitlements: sampleEntitlements)))
        XCTAssertEqual(read["com.apple.developer.icloud-container-environment"] as? String, "Production")
        XCTAssertEqual(read["beta-reports-active"] as? Bool, true)
        XCTAssertEqual(read["aps-environment"] as? String, "production")

        // A universal binary: the first architecture's signature.
        let thin = machO(entitlements: sampleEntitlements)
        let fat = be32(0xCAFE_BABE) + be32(1) + be32(0x0100_000C) + be32(0) + be32(0x4000) + be32(UInt32(thin.count)) + be32(14)
        let universal = fat + Data(count: 0x4000 - fat.count) + thin
        XCTAssertEqual(CodeSignature.entitlements(inExecutable: universal)?["beta-reports-active"] as? Bool, true)
    }

    func testAnythingElseReadsAsNoEntitlements() {
        XCTAssertNil(CodeSignature.entitlements(inExecutable: machO(entitlements: nil)), "unsigned")
        XCTAssertNil(CodeSignature.entitlements(inExecutable: Data("not a binary".utf8)))
        XCTAssertNil(CodeSignature.entitlements(inExecutable: Data()))
        let whole = machO(entitlements: sampleEntitlements)
        for cut in stride(from: 0, to: whole.count, by: 7) {
            XCTAssertNil(CodeSignature.entitlements(inExecutable: whole.prefix(cut)), "cut at \(cut) of \(whole.count)")
        }
    }

    /// The test host is the app itself: its executable's signature is what a Debug build carries.
    func testThisAppsOwnSignatureIsReadable() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["HITLIST_UNSIGNED"] != nil, "unsigned builds carry no entitlements")
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let read = CodeSignature.entitlements(ofExecutableAt: executable)
        #if os(macOS)
        let entitlements = try XCTUnwrap(read, "the Mac Debug build is signed with its entitlements")
        XCTAssertEqual(entitlements[SyncEnvironment.cloudKitEnvironmentKey] as? String, "Development")
        XCTAssertEqual(entitlements[SyncEnvironment.macGetTaskAllowKey] as? Bool, true)
        #else
        if let read { XCTAssertNotEqual(read[SyncEnvironment.cloudKitEnvironmentKey] as? String, "Production") }
        #endif
    }
}

/// The words of Settings → iCloud → Sync log (brief 25, item 5): row times, details, the export's header.
final class SyncLogTextTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-02 17:17:49.677 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_639_869.677)

    func testRowTimesUseA24HourClockAndADateBeforeToday() {
        XCTAssertEqual(SyncLogText.rowTime(now, now: now, timeZone: utc), "17:17:49")
        XCTAssertEqual(SyncLogText.rowTime(now.addingTimeInterval(-6 * 3600), now: now, timeZone: utc), "11:17:49")
        let nov1 = Date(timeIntervalSince1970: 1_793_558_314) // 2026-11-01 18:38:34 UTC
        XCTAssertEqual(SyncLogText.rowTime(nov1, now: now, timeZone: utc), "Nov 1, 18:38:34")
    }

    func testRowDetailIsTheKindThenTheFields() {
        let entry = SyncLogEntry(seq: 1, date: now, pid: 1, kind: .event, level: .info, message: "export finished in 0.70 s",
                                 fields: ["id": "9D6205C0", "duration": "0.70 s", "afterSave": "0.72 s"])
        XCTAssertEqual(SyncLogText.rowDetail(entry), "CloudKit · afterSave=0.72 s · duration=0.70 s · id=9D6205C0")
        let bare = SyncLogEntry(seq: 2, date: now, pid: 1, kind: .scene, level: .info, message: "App active")
        XCTAssertEqual(SyncLogText.rowDetail(bare), "App")
    }

    func testNewestFirstBreaksTiesBySequence() {
        let a = SyncLogEntry(seq: 1, date: now, pid: 1, kind: .note, level: .info, message: "a")
        let b = SyncLogEntry(seq: 2, date: now, pid: 1, kind: .note, level: .info, message: "b")
        let c = SyncLogEntry(seq: 3, date: now.addingTimeInterval(-1), pid: 1, kind: .note, level: .info, message: "c")
        XCTAssertEqual([c, a, b].sorted(by: SyncLogText.newestFirst).map(\.message), ["b", "a", "c"])
    }

    func testTheExportStartsWithAHeader() {
        let env = SyncEnvironment(cloudKit: .production, push: "production", channel: .testFlight, build: "11")
        let header = SyncLogText.header(now: now, environment: env, timeZone: utc)
        XCTAssertEqual(header.first, "HITList sync log")
        XCTAssertTrue(header[1].hasPrefix("HITList \(AppInfo.versionLabel) · "), header[1])
        XCTAssertEqual(header[2], "CloudKit: Production · TestFlight build 11")
        XCTAssertEqual(header[3], "Exported 2026-11-02 17:17:49 Z")
        XCTAssertEqual(SyncLogText.fileName(now: now, timeZone: utc), "HITList sync log 2026-11-02")
    }

    func testTheFullTextIsOldestFirstUnderTheHeader() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "SyncLogTextTests-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = SyncLog(url: url, mirrorToOSLog: false)
        log.record(.note, "second", date: now)
        log.record(.note, "first", date: now.addingTimeInterval(-60))
        let lines = SyncLogText.full(log).components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "HITList sync log")
        let first = try XCTUnwrap(lines.firstIndex { $0.hasSuffix("first") })
        let second = try XCTUnwrap(lines.firstIndex { $0.hasSuffix("second") })
        XCTAssertLessThan(first, second, "sorted by time, whatever order the lines were written in")
    }
}

/// A thread-safe step counter for the injected clock.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = -1
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
