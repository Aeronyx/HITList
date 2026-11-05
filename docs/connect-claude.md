---
title: Use HITList with Claude
permalink: /claude/
---

# Use HITList with Claude

HITList on the Mac can let Claude read and update your tasks: Claude Desktop and Claude Code can list
tasks with HITList's filters ("today | overdue", "#Work & 7 days"), add tasks with quick-add text
("Call the dentist tomorrow 9am p2 #Health"), complete them and change them. You choose which tasks Claude
sees. It is off until you turn it on, and Claude can never delete a task.

It works while HITList is open on your Mac. On the iPhone and iPad, turning it on gives you the same privacy
choice and **Copy for Claude**, which copies the tasks Claude may see as JSON to paste into any chat.

## 1. Turn on Claude integration

In HITList, open **Settings → Claude** (on the Mac: Settings, then **Claude** in the list on the left) and
turn on **Claude integration**. HITList says what Claude will be able to see and do; choose **Turn On**.
While it is off, nothing on your Mac can reach your tasks through HITList, and Copy for Claude is hidden.

## 2. Choose what Claude sees

Once it is on, Settings → Claude shows the rest:

- **All but @private** (the default): Claude sees every task except those labelled `@private`.
- **Only @claude**: Claude sees only tasks labelled `@claude`. Tasks Claude adds get the label, so it can
  find them again.

You can rename either label in the row below the choice. A hidden task's subtasks are hidden with it, and a
Group whose tasks are all hidden is never named to Claude. **Visible now** shows how many open tasks
Claude can see.

## 3a. Connect Claude Desktop

1. In Settings → Claude, under **Claude Desktop**, click **Copy**.
2. In the Claude app: **Claude → Settings… → Developer → Edit Config**. This opens
   `~/Library/Application Support/Claude/claude_desktop_config.json` in Finder; open it in TextEdit.
3. If the file is empty or holds only `{}`, replace everything with what you copied. If it already has an
   `"mcpServers"` section, add the `"hitlist"` entry inside it.
4. Save, then quit Claude (⌘Q) and open it again.
5. In a new chat, click the tools button: **hitlist** is listed. Try "What's due today in HITList?"

The entry looks like this:

```json
{
  "mcpServers": {
    "hitlist": {
      "command": "/Applications/HITList.app/Contents/MacOS/hitlist-mcp"
    }
  }
}
```

## 3b. Connect Claude Code

In Settings → Claude, under **Claude Code**, click **Copy**, paste it into Terminal and press Return:

```
claude mcp add --scope user hitlist -- /Applications/HITList.app/Contents/MacOS/hitlist-mcp
```

`claude mcp list` then shows **hitlist**. Every Claude Code session can use it.

## Check it works

- In Settings → Claude, click **Test connection**. "Connected" means Claude can reach HITList.
- Or in Terminal: `/Applications/HITList.app/Contents/MacOS/hitlist-mcp --check`

If Claude says "HITList isn't running on this Mac", open HITList. If it says "Claude integration is off
in HITList", turn on Claude integration in Settings → Claude.

## What Claude can do

| Tool | What it does |
|---|---|
| list_tasks | Lists open tasks, optionally with a HITList filter, completed ones on request |
| get_task | One task with its description and subtasks |
| add_task | Adds a task from quick-add text, exactly as HITList's own quick add reads it |
| complete_task | Completes a task (a repeating task moves to its next date); reopen it from Completed in HITList |
| update_task | Changes the title, description, due date, priority, labels or Group |
| list_groups, list_labels | The Groups and labels Claude can see |

Every change Claude makes is noted in HITList's sync log (Settings → iCloud → Sync log) without the task's
text.

## Privacy

HITList itself sends nothing anywhere. The connector is a small program inside HITList.app that Claude
starts on your Mac; it talks only to HITList on the same Mac and never opens your task database itself.
What Claude reads is sent to Anthropic as part of your conversation, under your Claude account's terms.
Tasks you hide are never given to Claude. Turn off Claude integration, or remove the `hitlist` entry from Claude,
to stop.
