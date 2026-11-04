import Foundation
import HITListCore

// hitlist-mcp: HITList's MCP server for Claude Desktop and Claude Code (brief 43). Shipped inside the Mac
// app (HITList.app/Contents/MacOS/hitlist-mcp); Claude starts it and talks MCP over stdin/stdout, one
// JSON-RPC message per line. It answers `initialize` and `tools/list` itself, so Claude always sees the
// tools, and hands each tool call to the running app through the app group's message port
// (`ClaudeWire`). It never opens the task store: the app does every read and write on its own main
// context. Sandboxed like the app, with only the app group: it can reach HITList and nothing else.
//
//   hitlist-mcp                  serve MCP on stdin/stdout (what Claude runs)
//   hitlist-mcp --check          say whether HITList answers, then exit
//   hitlist-mcp --store <name>   talk to an app on a side store (HITLIST_STORE_SUFFIX), e.g. a Debug build

let groupID = "UC8N98H3RT.com.trammells.hitlist"

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

/// The app's version, read from the bundle this helper sits in (Contents/MacOS/hitlist-mcp).
let version: String = {
    let app = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let info = Bundle(url: app)?.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
    return (info?["CFBundleVersion"] as? String).map { "\(short) (\($0))" } ?? short
}()

func printError(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
        hitlist-mcp \(version): HITList's MCP server for Claude. Claude Desktop and Claude Code start it.
          --check          say whether HITList answers, then exit
          --store <name>   use the HITList app on a side store (a Debug build: Development)
          --version        print the version
        """)
    exit(0)
}
if arguments.contains("--version") {
    print(version)
    exit(0)
}

let storeSuffix = ClaudeWire.cleanSuffix(option("--store") ?? ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"])
let bridge = ClaudeHelperBridge.live(groupID: groupID, storeSuffix: storeSuffix)

if arguments.contains("--check") {
    let result = bridge.call(ClaudeTools.listGroups, [:])
    if result.isError {
        print(result.text)
        exit(1)
    }
    print("HITList answered. Claude can use it.")
    exit(0)
}

let server = MCPServer(name: ClaudeTools.serverName, title: ClaudeTools.serverTitle, version: version,
                       instructions: ClaudeTools.instructions, tools: ClaudeTools.all) { name, arguments in
    bridge.call(name, arguments)
}

// Replies go out whole, one line each; stdout is unbuffered so Claude never waits on a partial line.
setvbuf(stdout, nil, _IONBF, 0)
func write(_ reply: Data?) {
    guard let reply else { return }
    FileHandle.standardOutput.write(reply + Data([0x0A]))
}

var buffer = MCPLineBuffer()
let input = FileHandle.standardInput
while true {
    let chunk = input.availableData
    if chunk.isEmpty {
        // End of input: Claude closed the pipe. Answer a last line that came without a newline.
        if let last = buffer.finish() { write(server.handle(line: last)) }
        break
    }
    for line in buffer.append(chunk) { write(server.handle(line: line)) }
}
exit(0)
