# dev

How work on HITList is run. Nothing here ships in the app.

- `SUPERVISOR.md`: the handbook. Environment, the rules that must not break (the CloudKit schema above
  all), how a round goes from feedback to release, where things live, and the product decisions already
  made.
- `briefs/`: one file per piece of delegated work, numbered in order. Each has the request in the
  owner's words, numbered items, the files it may touch and what done looks like. `briefs/COMMON.md` is
  the shared context every session reads first; `briefs/HIG-NOTES.md` is a digest of Apple's design
  guidelines for the screens the app has.
- `ROADMAP.md`: the plan and a row per finished brief, with how it was verified.
- `DESIGN.md`: the original design from October 2026, kept as written.

A round: the owner uses a build and writes notes; the notes are split into briefs so that no two touch
the same code; sessions implement them in parallel worktrees and report back; the branches are merged,
all suites run, the app is exercised by hand; release notes are written; the owner runs `release.sh`.
