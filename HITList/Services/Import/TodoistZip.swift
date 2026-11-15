import Foundation
import Compression
import HITListCore

/// Brief 137: just enough of the ZIP format to open a Todoist backup without asking anyone to unzip it. Entries are
/// found through the central directory at the end of the file; stored (method 0) and deflated (method 8) entries
/// are read, deflate through the Compression framework's raw DEFLATE (`COMPRESSION_ZLIB`). Anything else (ZIP64,
/// encryption, other methods) is refused with a plain sentence.
enum TodoistZip {
    struct Entry: Equatable {
        let name: String
        let data: Data
    }

    enum ZipError: Error, LocalizedError, Equatable {
        case notAZip
        case damaged
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: return "This is not a ZIP file."
            case .damaged: return "The ZIP file is damaged or incomplete. Download the backup from Todoist again."
            case .unsupported(let what): return "This ZIP uses \(what), which HITList cannot open. Unzip it and choose the CSV files instead."
            }
        }
    }

    /// The largest entry read: a backup's CSVs are small, and a bigger one is not Todoist's.
    static let maxEntrySize = 64 * 1024 * 1024

    static func isZip(_ data: Data) -> Bool { data.count >= 4 && data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]) }

    static func entries(of data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22, isZip(data) else { throw ZipError.notAZip }
        func u16(_ at: Int) throws -> Int {
            guard at >= 0, at + 2 <= bytes.count else { throw ZipError.damaged }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8
        }
        func u32(_ at: Int) throws -> Int {
            guard at >= 0, at + 4 <= bytes.count else { throw ZipError.damaged }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }

        // The end-of-central-directory record: the last 22 bytes, or before a comment of up to 64 KB.
        var end = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        while i >= lowest {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { end = i; break }
            i -= 1
        }
        guard end >= 0 else { throw ZipError.damaged }
        let count = try u16(end + 10)
        let directorySize = try u32(end + 12)
        let directoryOffset = try u32(end + 16)
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF { throw ZipError.unsupported("ZIP64") }
        guard directoryOffset + directorySize <= end else { throw ZipError.damaged }

        var entries: [Entry] = []
        var at = directoryOffset
        for _ in 0..<count {
            guard try u32(at) == 0x0201_4B50 else { throw ZipError.damaged }
            let flags = try u16(at + 8)
            let method = try u16(at + 10)
            let compressedSize = try u32(at + 20)
            let size = try u32(at + 24)
            let nameLength = try u16(at + 28)
            let extraLength = try u16(at + 30)
            let commentLength = try u16(at + 32)
            let localOffset = try u32(at + 42)
            guard at + 46 + nameLength <= bytes.count else { throw ZipError.damaged }
            let nameBytes = Array(bytes[(at + 46)..<(at + 46 + nameLength)])
            // Bit 11: UTF-8 names. Without it the name is CP437, which is ASCII for any name Todoist writes.
            let name = String(bytes: nameBytes, encoding: flags & 0x800 != 0 ? .utf8 : .isoLatin1) ?? String(decoding: nameBytes, as: UTF8.self)
            at += 46 + nameLength + extraLength + commentLength

            if name.hasSuffix("/") { continue } // a folder
            if flags & 0x1 != 0 { throw ZipError.unsupported("a password") }
            guard size <= maxEntrySize, compressedSize <= maxEntrySize else { throw ZipError.unsupported("a file over 64 MB") }

            guard try u32(localOffset) == 0x0403_4B50 else { throw ZipError.damaged }
            let start = localOffset + 30 + (try u16(localOffset + 26)) + (try u16(localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw ZipError.damaged }
            let raw = Data(bytes[start..<(start + compressedSize)])

            switch method {
            case 0:
                guard raw.count == size else { throw ZipError.damaged }
                entries.append(Entry(name: name, data: raw))
            case 8:
                entries.append(Entry(name: name, data: try inflate(raw, size: size)))
            default:
                throw ZipError.unsupported("compression method \(method)")
            }
        }
        return entries
    }

    private static func inflate(_ raw: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            raw.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, size, s, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.damaged }
        return out
    }
}

/// The files a person picked (a backup ZIP, one or several CSVs) as Todoist projects, in the order given.
enum TodoistFiles {
    struct File {
        let name: String
        let data: Data
    }

    enum FileError: Error, LocalizedError, Equatable {
        case notTodoist(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notTodoist(let name): return "\(name) is not a file from Todoist. Choose a backup (.zip) or a project's CSV."
            case .unreadable(let name): return "\(name) could not be read as text (Todoist writes UTF-8)."
            }
        }
    }

    static func projects(from files: [File]) throws -> [TodoistProject] {
        var projects: [TodoistProject] = []
        for file in files {
            if TodoistZip.isZip(file.data) {
                let csvs = try TodoistZip.entries(of: file.data).filter { entry in
                    let last = (entry.name as NSString).lastPathComponent
                    return entry.name.lowercased().hasSuffix(".csv") && !entry.name.hasPrefix("__MACOSX/") && !last.hasPrefix("._")
                }
                guard !csvs.isEmpty else { throw FileError.notTodoist(file.name) }
                for csv in csvs { projects.append(try project(name: csv.name, data: csv.data, shownAs: file.name)) }
            } else {
                projects.append(try project(name: file.name, data: file.data, shownAs: file.name))
            }
        }
        return projects
    }

    private static func project(name: String, data: Data, shownAs: String) throws -> TodoistProject {
        guard let text = String(data: data, encoding: .utf8) else { throw FileError.unreadable(shownAs) }
        do { return try TodoistReader.read(csv: text, fileName: name) }
        catch { throw FileError.notTodoist(shownAs) }
    }
}
