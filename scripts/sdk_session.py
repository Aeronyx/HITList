#!/usr/bin/env python3
"""Run one HITList brief as an Opus 5.5 agent through the Claude Agent SDK, with a guarded tool policy.

Why the SDK and not the `claude` CLI: George's promotional API credit applies to "Agent SDK, API,
Batch API, Playground, Managed Agents" and not to Claude Code, so CLI sessions on the API key fail
with "Credit balance too low" while SDK sessions are billed to the promo (verified 2026-10-31 with a
one-turn query). The SDK is Claude Code's engine as a library: same tools, same session storage
(~/.claude/projects/<cwd>), so `--continue` picks up a conversation the CLI started in that folder.

Permission policy (unattended, so it is explicit rather than "bypass everything"):
  - File tools (Read/Edit/Write/MultiEdit/Glob/Grep/NotebookEdit) are allowed only on paths inside the
    worktree, plus read-only access to the main checkout and DerivedData for logs.
  - Bash is allowed only when the command's programs are on the allowlist below (build, test, git
    local, xcodegen, simulator, log reading, afconvert/afplay, python3 for sound generation, etc.),
    and it never mentions git push, gh, altool, scripts/release.sh, sudo, or rm -rf of anything
    outside the worktree. Everything else is denied with a message the agent can read and adapt to.

Invoked by scripts/session.sh; direct use:
  sdk_session.py <worktree> <brief-file> <effort> [--model claude-opus-5-5] [--continue [MESSAGE]]
                 [--max-budget-usd N]
"""
import argparse, asyncio, pathlib, re, shlex, signal, sys

try:
    import claude_agent_sdk as sdk
except ImportError:
    sys.exit("claude-agent-sdk is not installed in this interpreter; scripts/session.sh sets up the venv.")

OPENING = ("Read briefs/COMMON.md, then briefs/{brief}, and carry it out completely, following every "
           "rule in both. You are running unattended through the Agent SDK: never wait for a human, "
           "never ask questions, and finish with the full final report the brief asks for. Shell "
           "commands are limited to building, testing, local git, xcodegen, the simulator and log "
           "reading; if one is denied, do the task another allowed way or note it in the report.")

ALLOWED_PROGRAMS = {
    "xcodebuild", "xcrun", "swift", "xcodegen", "git", "ls", "cat", "head", "tail", "grep", "rg", "find",
    "wc", "sed", "awk", "sort", "uniq", "cut", "tr", "diff", "echo", "printf", "pwd", "cd", "mkdir",
    "cp", "mv", "touch", "chmod", "test", "[", "true", "false", "python3", "python", "afconvert",
    "afinfo", "afplay", "plutil", "codesign", "open", "sqlite3", "date", "sleep", "env", "export",
    "which", "file", "stat", "tee", "xargs", "basename", "dirname", "realpath", "/usr/bin/log",
    "scripts/test.sh", "./scripts/test.sh", "defaults", "killall", "pkill", "jq", "base64", "shasum",
    "ditto", "zip", "unzip", "tar", "timeout", "gtimeout", "actionlint", "brew", "uv", "pip3",
}
FORBIDDEN = re.compile(r"(git\s+push|\bgh\b|altool|notarytool|release\.sh|\bsudo\b|rm\s+-rf\s+/(?!tmp|private/tmp)|"
                       r"rm\s+-rf\s+~|xcrun\s+simctl\s+erase\s+all|>\s*/dev/sd|curl\s+.*-X\s*(POST|PUT)|security\s+)",
                       re.I)

def programs_in(command: str) -> set[str]:
    """First word of every simple command in a shell line (splits on ;, &&, ||, |)."""
    found = set()
    for part in re.split(r"\s*(?:;|&&|\|\||\|)\s*", command):
        try:
            words = shlex.split(part, posix=True)
        except ValueError:
            return {"<unparseable>"}
        words = [w for w in words if not re.match(r"^[A-Z_][A-Z0-9_]*=", w)]  # skip VAR=value prefixes
        if words:
            found.add(words[0])
    return found

def make_policy(worktree: pathlib.Path, root: pathlib.Path):
    readable_roots = [worktree, root, pathlib.Path.home() / "Library/Developer/Xcode/DerivedData",
                      pathlib.Path("/private/tmp"), pathlib.Path("/tmp"), pathlib.Path.home() / "Desktop/HITList-videos"]
    writable_roots = [worktree, pathlib.Path("/private/tmp"), pathlib.Path("/tmp"), pathlib.Path.home() / "Desktop/HITList-videos"]

    def inside(p: str, roots) -> bool:
        try:
            rp = pathlib.Path(p).expanduser().resolve()
        except Exception:
            return False
        return any(rp == r or r in rp.parents for r in roots)

    async def can_use_tool(tool: str, tool_input: dict, _ctx):
        if tool in ("Read", "Glob", "Grep", "LS", "NotebookRead"):
            p = tool_input.get("file_path") or tool_input.get("path") or str(worktree)
            if inside(p, readable_roots):
                return sdk.PermissionResultAllow()
            return sdk.PermissionResultDeny(message=f"Reading outside the worktree is not allowed: {p}")
        if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
            p = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
            if inside(p, writable_roots):
                return sdk.PermissionResultAllow()
            return sdk.PermissionResultDeny(message=f"Writing outside the worktree is not allowed: {p}")
        if tool == "Bash":
            cmd = tool_input.get("command", "")
            if FORBIDDEN.search(cmd):
                return sdk.PermissionResultDeny(message="That command is not allowed in an unattended session (no push, gh, upload, release, sudo or destructive rm).")
            progs = programs_in(cmd)
            bad = {p for p in progs if p not in ALLOWED_PROGRAMS and not p.startswith(("./", "/Applications/Xcode"))}
            if bad:
                return sdk.PermissionResultDeny(message=f"Program(s) not on the allowlist: {', '.join(sorted(bad))}. Use the build/test/git-local tools listed in the brief.")
            return sdk.PermissionResultAllow()
        if tool in ("TodoWrite", "Task", "WebFetch", "WebSearch", "Skill"):
            return sdk.PermissionResultAllow()
        return sdk.PermissionResultDeny(message=f"Tool {tool} is not enabled in unattended sessions.")
    return can_use_tool

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("worktree"); ap.add_argument("brief")
    ap.add_argument("effort", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--model", default="claude-opus-5-5")
    ap.add_argument("--continue", dest="resume", nargs="?", const="", default=None, metavar="MESSAGE",
                    help="resume the most recent conversation in the worktree, optionally sending MESSAGE first")
    ap.add_argument("--max-budget-usd", type=float, default=None)
    a = ap.parse_args()

    wt = pathlib.Path(a.worktree).resolve()
    root = pathlib.Path(__file__).resolve().parent.parent
    if not (wt / "briefs" / a.brief).is_file():
        sys.exit(f"no such brief: {wt / 'briefs' / a.brief}")
    if a.resume is None:
        prompt = OPENING.format(brief=a.brief)
    else:
        prompt = a.resume or ("Continue where you left off and finish the task, then give the final report "
                              "per briefs/COMMON.md.")

    options = sdk.ClaudeAgentOptions(
        cwd=str(wt), model=a.model, effort=a.effort,
        permission_mode="acceptEdits",
        can_use_tool=make_policy(wt, root),
        setting_sources=["user", "project"],
        continue_conversation=a.resume is not None,
        max_budget_usd=a.max_budget_usd,
        # A Read of a simulator screenshot comes back as one JSON message over the SDK's 1 MB default and
        # killed two sessions ("JSON message exceeded maximum buffer size"); allow large tool results.
        max_buffer_size=64 * 1024 * 1024,
    )
    print(f"▸ {'resuming' if a.resume is not None else 'starting'} {a.model} effort={a.effort} in {wt}", flush=True)

    async def run() -> int:
        code = 1
        async for m in sdk.query(prompt=prompt, options=options):
            if isinstance(m, sdk.AssistantMessage):
                for b in m.content:
                    if isinstance(b, sdk.TextBlock) and b.text.strip():
                        print(b.text, flush=True)
                    elif isinstance(b, sdk.ToolUseBlock):
                        short = str(b.input.get("command") or b.input.get("file_path") or b.input.get("pattern") or "")[:110]
                        print(f"  · {b.name} {short}", flush=True)
            elif isinstance(m, sdk.ResultMessage):
                print(f"\n■ {m.subtype} · turns={m.num_turns} · cost=${(m.total_cost_usd or 0):.2f} · "
                      f"{(m.duration_ms or 0)//60000} min", flush=True)
                if m.is_error:
                    print("error:", getattr(m, "result", ""), flush=True)
                code = 1 if m.is_error else 0
        return code

    loop = asyncio.new_event_loop()
    try:
        loop.add_signal_handler(signal.SIGINT, lambda: sys.exit(130))
        return loop.run_until_complete(run())
    finally:
        loop.close()

if __name__ == "__main__":
    sys.exit(main())
