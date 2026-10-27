import Foundation
import SwiftData
import HITListCore

/// Pushes snapshots to the self-hosted backup receiver (see `server/`) and restores from it.
@MainActor
@Observable
final class BackupService {
    enum State: Equatable { case idle, working(String), failed(String), succeeded(String) }

    var state: State = .idle

    var serverURL: String {
        get { AppGroup.defaults.string(forKey: "backup.serverURL") ?? "" }
        set { AppGroup.defaults.set(newValue, forKey: "backup.serverURL") }
    }
    var token: String {
        get { Keychain.get("backup.token") ?? "" }
        set { newValue.isEmpty ? Keychain.delete("backup.token") : Keychain.set(newValue, for: "backup.token") }
    }
    var automaticBackupEnabled: Bool {
        get { AppGroup.defaults.bool(forKey: "backup.automatic") }
        set { AppGroup.defaults.set(newValue, forKey: "backup.automatic") }
    }
    var intervalHours: Int {
        get { max(1, AppGroup.defaults.integer(forKey: "backup.intervalHours").nonZero ?? 24) }
        set { AppGroup.defaults.set(newValue, forKey: "backup.intervalHours") }
    }
    private(set) var lastBackupAt: Date? {
        get { AppGroup.defaults.object(forKey: "backup.lastAt") as? Date }
        set { AppGroup.defaults.set(newValue, forKey: "backup.lastAt") }
    }

    var isConfigured: Bool { !serverURL.isEmpty && !token.isEmpty }

    private func endpoint(_ path: String) throws -> URL {
        var base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw BackupError.badURL
        }
        return url
    }

    private func request(_ path: String, method: String, body: Data? = nil) throws -> URLRequest {
        var req = URLRequest(url: try endpoint(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 30
        return req
    }

    /// Pushes a snapshot now. Returns the stored filename reported by the server.
    @discardableResult
    func backupNow(context: ModelContext) async -> Bool {
        guard isConfigured else { state = .failed("Set the server URL and token first."); return false }
        state = .working("Building snapshot…")
        do {
            let snapshot = try SnapshotBuilder.build(from: context)
            let data = try snapshot.jsonData()
            state = .working("Uploading \(snapshot.tasks.count) tasks…")
            let (respData, resp) = try await URLSession.shared.data(for: try request("/snapshot", method: "PUT", body: data))
            guard let http = resp as? HTTPURLResponse else { throw BackupError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw BackupError.server(http.statusCode, String(decoding: respData, as: UTF8.self))
            }
            lastBackupAt = Date()
            let stored = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any])?["stored"] as? String
            state = .succeeded("Backed up \(snapshot.tasks.count) tasks" + (stored.map { " as \($0)" } ?? ""))
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    /// Pulls the latest snapshot from the server and merges it (newer records win).
    func restoreLatest(context: ModelContext) async {
        guard isConfigured else { state = .failed("Set the server URL and token first."); return }
        state = .working("Downloading latest snapshot…")
        do {
            let (data, resp) = try await URLSession.shared.data(for: try request("/snapshot/latest", method: "GET"))
            guard let http = resp as? HTTPURLResponse else { throw BackupError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw BackupError.server(http.statusCode, String(decoding: data, as: UTF8.self))
            }
            let snapshot = try Snapshot.from(json: data)
            let summary = try SnapshotBuilder.restore(snapshot, into: context)
            state = .succeeded("Restored from \(snapshot.deviceName): \(summary.description)")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func testConnection() async {
        state = .working("Checking server…")
        do {
            let (data, resp) = try await URLSession.shared.data(for: try request("/snapshots", method: "GET"))
            guard let http = resp as? HTTPURLResponse else { throw BackupError.badResponse }
            guard http.statusCode == 200 else { throw BackupError.server(http.statusCode, String(decoding: data, as: UTF8.self)) }
            let count = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["snapshots"] as? [Any])?.count ?? 0
            state = .succeeded("Connected. Server holds \(count) snapshot\(count == 1 ? "" : "s").")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Called when the app becomes active; backs up if the interval has elapsed.
    func backupIfDue(context: ModelContext) async {
        guard automaticBackupEnabled, isConfigured else { return }
        if let last = lastBackupAt, Date().timeIntervalSince(last) < Double(intervalHours) * 3600 { return }
        await backupNow(context: context)
    }

    enum BackupError: LocalizedError {
        case badURL, badResponse
        case server(Int, String)
        var errorDescription: String? {
            switch self {
            case .badURL: return "The server URL must start with http:// or https://."
            case .badResponse: return "The server returned an unexpected response."
            case .server(let code, let body):
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
                return code == 401 ? "The server rejected the token." : "Server error \(code): \(trimmed)"
            }
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
