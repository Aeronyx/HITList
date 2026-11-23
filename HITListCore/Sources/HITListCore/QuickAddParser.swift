import Foundation

/// One recognized span inside the quick-add text, so the UI can highlight it.
public struct QuickAddToken: Equatable, Sendable {
    public enum Kind: String, Sendable { case priority, project, label, date, time, recurrence, reminder }
    public var kind: Kind
    public var range: Range<String.Index>
    public var text: String
    /// Overridden by a later phrase of the same kind (brief 37: "p1 … p3", "jan 6 … in a month"): not
    /// highlighted, sets nothing, its words are title text. It applies again once every later phrase of its
    /// kind is switched off (`parse(_:disabling:)`).
    public var isSuperseded = false

    /// Said in plain language rather than typed as a code (brief 175): "remind me in an hour", "reminder 1 hour
    /// before", "Remind me to", "priority 1", "remind me at 5pm" when it became the due time (a time token), and the
    /// same after a dictated lead-in ("Can you remind me at 5").
    var isSaidInWords: Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("remind") || lower.hasPrefix("priority") { return true }
        return ReminderPhrase.leadIn(lower.split(whereSeparator: \.isWhitespace).map(String.init), at: 0) > 0
    }
}

public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var priority: Priority
    public var projectName: String?
    public var labelNames: [String]
    public var recurrence: RecurrenceRule?
    /// Minutes before the due time to remind (`!15mb`, `!15 minutes before`); 0 for `!0` / `!at` / `!At time of task`
    /// (and "Remind me to …" with a time, brief 175); nil when nothing was typed.
    public var reminderOffsetMinutes: Int?
    /// A reminder that long from now (`!15m`, `!In 15 minutes`, brief 48), whatever the due date; nil when none was typed.
    public var reminderFromNow: ReminderSpan?
    /// A reminder at a clock time (`!4pm`, `!4:00 PM`, "remind me at 4pm", brief 175); nil when none was typed.
    public var reminderClock: ReminderClock?
    /// When the task's own reminder goes off: `reminderFromNow` from the parser's `now`, or `reminderClock` on its day
    /// (`ReminderClock.date`). Saved as the task's `reminderDate`.
    public var reminderDate: Date?
    /// A deadline picked from the card's "+" menu. It has no text token, so the parser never sets it.
    public var deadline: Date?
    /// A location typed from the card's "+" menu. It has no text token, so the parser never sets it.
    public var locationName: String?
    public var tokens: [QuickAddToken]

    public init(title: String = "", dueDate: Date? = nil, hasDueTime: Bool = false, priority: Priority = .p4,
                projectName: String? = nil, labelNames: [String] = [], recurrence: RecurrenceRule? = nil,
                reminderOffsetMinutes: Int? = nil, deadline: Date? = nil, locationName: String? = nil,
                tokens: [QuickAddToken] = [], reminderFromNow: ReminderSpan? = nil, reminderDate: Date? = nil,
                reminderClock: ReminderClock? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priority = priority
        self.projectName = projectName
        self.labelNames = labelNames
        self.recurrence = recurrence
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.deadline = deadline
        self.locationName = locationName
        self.tokens = tokens
        self.reminderFromNow = reminderFromNow
        self.reminderDate = reminderDate
        self.reminderClock = reminderClock
    }
}

/// Turns "Pay rent tomorrow 5pm p1 #Finance @bills every month !1hb" into structured fields.
public struct QuickAddParser: Sendable {
    public var dateParser: DateExpressionParser
    public var knownProjects: [String]
    public var knownLabels: [String]
    /// The task already has a due time (the task editor's title, brief 65): a reminder before the due time
    /// ("!15mb", "!at") counts without a time typed beside it. Off for quick add, where the text is the task.
    public var dueTimeIsSet = false
    /// A reminder said in words leaves its lead ("Remind me", "Reminder", a dictated lead-in before it) out of its
    /// token, as the title: how `parse` reads a text with nothing else for a title (the second review of brief 175).
    var leadIsTitle = false
    /// The task already has a day of its own (the task editor's task with a date, an Upcoming day's row): "at 1" to
    /// "at 6" with no am or pm is the afternoon, as beside a day typed (`hour(_:_:words:hasDay:)`). Off for quick add on its own.
    public var dueDayIsSet = false

    public init(now: Date = Date(), calendar: Calendar = .current, knownProjects: [String] = [], knownLabels: [String] = [],
                weekStart: Int = 2) {
        self.dateParser = DateExpressionParser(calendar: calendar, now: now, weekStart: weekStart)
        self.knownProjects = knownProjects
        self.knownLabels = knownLabels
    }

    struct Word {
        let text: String
        let lower: String
        let range: Range<String.Index>
    }

    /// Splits on whitespace but keeps `#"Two Words"` and `"quoted text"` together.
    static func words(in input: String) -> [Word] {
        var result: [Word] = []
        var i = input.startIndex
        while i < input.endIndex {
            while i < input.endIndex, input[i].isWhitespace { i = input.index(after: i) }
            guard i < input.endIndex else { break }
            let start = i
            var inQuotes = false
            while i < input.endIndex {
                let c = input[i]
                if c == "\"" { inQuotes.toggle() }
                else if c.isWhitespace && !inQuotes { break }
                i = input.index(after: i)
            }
            let text = String(input[start..<i])
            result.append(Word(text: text, lower: text.lowercased(), range: start..<i))
        }
        return result
    }

    /// How finished the text is (brief 48, George: a "!" phrase "only checks/adds a highlight after the user
    /// presses space instead of while they're typing it").
    public enum Mode: Sendable {
        /// Confirm, Siri, Claude: the end of the text ends the last word, so "Call mom !15m" sets the reminder.
        case final
        /// The quick-add card while it is typed in: a "!" word (`!15m`, `!15mb`, `!at`, `!!1`) at the very end,
        /// with no whitespace after it yet, is still being typed and stays plain title text.
        case live
    }

    /// The text read. Words said in plain language ("Remind me in an hour", "Priority 3") that would leave no title are
    /// the title, and set nothing (the review of brief 175): a task has a title (`parse(_:mode:isOff:)` masks them as a
    /// switched-off phrase is masked).
    public func parse(_ input: String, mode: Mode = .final) -> QuickAddResult {
        let result = scan(input, mode: mode)
        guard Self.leavesNoTitle(result, in: input, mode: mode) else { return result }
        return parse(input, mode: mode) { _, _ in false }
    }

    /// The title is empty and words said in plain language took it: they give it back. Not in the card's live reading
    /// while such a phrase ends in "to" with a space after it ("Remind me to |", "Remind me in an hour to |"): the title
    /// is what comes next, and the phrase stays lit rather than go dark for that one keystroke.
    static func leavesNoTitle(_ result: QuickAddResult, in input: String, mode: Mode) -> Bool {
        guard result.title.isEmpty else { return false }
        let spoken = result.tokens.filter { $0.isSaidInWords && !$0.isSuperseded }
        guard !spoken.isEmpty else { return false }
        if mode == .live, input.last?.isWhitespace == true,
           spoken.contains(where: { DateExpressionParser.normalize(String($0.text.split(separator: " ").last ?? "")) == "to" }) {
            return false
        }
        return true
    }

    /// One reading of the text, word by word (`parse` adds what reads the whole result).
    func scan(_ input: String, mode: Mode) -> QuickAddResult {
        let words = Self.words(in: input)
        let lowers = words.map(\.lower)
        var consumed = [Bool](repeating: false, count: words.count)
        var result = QuickAddResult()
        var time: (Int, Int)? = nil
        /// The time is "at 1" to "at 11" with no am or pm, its hour as typed: settled once the text is read (`hour`).
        var timeIsOpen = false
        var date: Date? = nil
        /// "in 2 hours": the due moment itself, unless a time is typed too (then that time on its day).
        var moment: Date? = nil
        /// The winning date came after "starting": the repeat's first day, not necessarily one it falls on.
        var dateIsStart = false
        /// The winning token of each kind that holds one value, by index in `result.tokens`. A reminder has
        /// two places (brief 48): one "from now" and one "before the due time" may stand side by side.
        var winner: [Slot: Int] = [:]
        /// The task's own reminder moment, the latest typed: that long from now, or a clock time (brief 175).
        var ownReminder: OwnReminder? = nil
        /// That clock time said with "remind me" (not a "!" code): its token, by index in `result.tokens`.
        var spokenClock: Int? = nil
        /// "Remind me to …" opens the text (brief 175): with a time and no other reminder, it reminds at the time.
        var remindMeTo = false
        /// Where a reminder said in words opens the text ("Remind me to call mom", "Remind me in 30 minutes to call
        /// mom"): while it stands, the title starts with a capital.
        var spokenStart: String.Index? = nil
        /// Words of superseded tokens: matched, so no other rule reads them, but title text.
        var supersededWords = Set<Int>()

        func mark(_ i: Int, _ n: Int, _ kind: QuickAddToken.Kind) {
            guard n > 0 else { return }
            let range = words[i].range.lowerBound..<words[i + n - 1].range.upperBound
            for k in i..<(i + n) { consumed[k] = true }
            result.tokens.append(QuickAddToken(kind: kind, range: range, text: String(input[range])))
        }

        /// `mark`, for a kind that holds one value: a later phrase overrides the earlier one (George,
        /// 2026-11-04), which stays in `tokens` as superseded and goes back to the title.
        func win(_ i: Int, _ n: Int, _ kind: QuickAddToken.Kind, slot: Slot? = nil) {
            let slot = slot ?? .kind(kind)
            if let earlier = winner[slot] {
                result.tokens[earlier].isSuperseded = true
                supersededWords.formUnion(words.indices.filter { result.tokens[earlier].range.contains(words[$0].range.lowerBound) })
            }
            mark(i, n, kind)
            winner[slot] = result.tokens.count - 1
        }

        var i = 0
        while i < words.count {
            if consumed[i] { i += 1; continue }
            let w = lowers[i]
            if mode == .live, w.hasPrefix("!"), words[i].range.upperBound == input.endIndex { i += 1; continue }

            // Priority: p1..p4, !!1..!!4; "priority 1" … "priority four" (brief 175)
            if let p = Self.priority(from: w) {
                result.priority = p; win(i, 1, .priority); i += 1; continue
            }
            if let p = Self.spokenPriority(lowers, at: i), endsTheWords(lowers, at: i + 2) {
                result.priority = p; win(i, 2, .priority); i += 2; continue
            }
            // Project: #Name, #"Two Words", or #two words matching a known project
            if w.hasPrefix("#"), w.count > 1 {
                let (name, n) = matchName(words: words, at: i, prefix: "#", known: knownProjects)
                result.projectName = name; win(i, n, .project); i += n; continue
            }
            // Label: @name
            if w.hasPrefix("@"), w.count > 1 {
                let (name, n) = matchName(words: words, at: i, prefix: "@", known: knownLabels)
                if !result.labelNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    result.labelNames.append(name)
                }
                mark(i, n, .label); i += n; continue
            }
            // Reminder: !15m / !2h / !1d from now; !15mb / !2hb / !1db before the due time, !0 / !at at it; and in words
            // (brief 175): "!10 minutes before", "!In 5 minutes", "!At time of task", "!4:00 PM", "remind me 30 minutes
            // before", "reminder in an hour". One token however many words. While its last word is still being typed at
            // the very end, the longest reading that ends before that word counts ("!at time" as "of task" is typed;
            // the review of brief 175: a phrase growing word by word never goes dark on the way); with none, all of
            // it is plain text.
            // A dictated lead-in ("Can you", "Please", "Hey Siri") before "remind me" at the start is the phrase's too
            // (the second review of brief 175): the title is the rest.
            let lead = i == 0 ? ReminderPhrase.leadIn(lowers, at: 0) : 0
            let afterPhrase = i > 0 && consumed[i - 1]
            if var reading = ReminderPhrase.reading(lowers, at: i + lead, atStart: i == 0, afterPhrase: afterPhrase) {
                if mode == .live, words[i + lead + reading.length - 1].range.upperBound == input.endIndex {
                    guard let shorter = ReminderPhrase.reading(Array(lowers.dropLast()), at: i + lead, atStart: i == 0,
                                                               afterPhrase: afterPhrase)
                    else { i += lead + reading.length; continue }
                    reading = shorter
                }
                let n = lead + reading.length
                // With nothing else for a title, the lead is the title and the rest the phrase (`leadIsTitle`).
                let spoken = !w.hasPrefix("!")
                let kept = leadIsTitle && spoken
                    ? lead + (DateExpressionParser.normalize(lowers[i + lead]) == "reminder" ? 1 : 2) : 0
                switch reading.phrase {
                case .fromNow(let span):
                    ownReminder = .span(span); win(i + kept, n - kept, .reminder, slot: .reminderFromNow); spokenClock = nil
                case .at(let clock):
                    ownReminder = .clock(clock, open: reading.openHour)
                    win(i + kept, n - kept, .reminder, slot: .reminderFromNow)
                    spokenClock = spoken ? result.tokens.count - 1 : nil
                case .beforeDue(let minutes):
                    result.reminderOffsetMinutes = minutes; win(i + kept, n - kept, .reminder, slot: .reminderBeforeDue)
                }
                if i == 0, spoken, kept == 0 { spokenStart = words[0].range.lowerBound }
                i += n; continue
            }
            // "Remind me to …" opening the text, a lead-in before it or not: the words are a token of their own (brief 175).
            if i == 0, Self.opensWithRemindMeTo(lowers, at: lead) {
                let n = lead + 3
                if mode == .live, words[n - 1].range.upperBound == input.endIndex { i += n; continue }
                mark(0, n, .reminder); remindMeTo = true; spokenStart = words[0].range.lowerBound; i += n; continue
            }
            // Recurrence
            if let (rule, n) = Self.matchRecurrence(lowers, at: i) {
                result.recurrence = rule; win(i, n, .recurrence); i += n; continue
            }
            // "in 10 minutes", "in two hours": a date token that sets the time as well
            if let (at, n) = dateParser.matchRelativeTime(in: lowers, at: i) {
                moment = at; date = dateParser.startOfDay(at); dateIsStart = false; win(i, n, .date); i += n; continue
            }
            // Time
            if let t = dateParser.matchTime(in: lowers, at: i, afternoonAfterAt: false) {
                time = (t.hour, t.minute); timeIsOpen = t.openHour; win(i, t.consumed, .time); i += t.consumed; continue
            }
            // Date (a plain day drops the moment of an earlier "in 2 hours"); "starting friday" too
            if let (pd, n, isStart) = matchDateOrStart(lowers, at: i) {
                let isTonight = DateExpressionParser.normalize(lowers[i + n - 1]) == "tonight"
                date = pd.date; moment = nil; dateIsStart = isStart; win(i, n, .date); i += n
                // A bare hour right after a date word is its time, on a 24-hour clock: "tom 13", "friday 9".
                // Only when no time is typed yet: a bare number is too weak to override "5pm". Not after "tonight",
                // where "9" would read 09:00 (brief 127): it stays in the title.
                if time == nil, !isTonight, i < words.count, !consumed[i],
                   let t = dateParser.matchTime(in: lowers, at: i, allowBareHour: true, afternoonAfterAt: false) {
                    time = (t.hour, t.minute); timeIsOpen = t.openHour; win(i, t.consumed, .time); i += t.consumed
                }
                continue
            }
            i += 1
        }

        // "Remind me at 5pm to call mom", "Call mom, remind me tomorrow at 9": a clock time said with "remind me", and no
        // day or time of the task's own (typed, or the editor's task's), is when the task is due, reminded at the time
        // (the review of brief 175: it made an undated task). Its words are a time token, or a date token with their
        // day. A repeat typed beside it gives the day. "!4pm" stays a reminder moment of its own.
        if case .clock(let clock, let open)? = ownReminder, let index = spokenClock, date == nil, time == nil, moment == nil,
           !dueDayIsSet {
            time = (clock.hour, clock.minute)
            timeIsOpen = open
            if let day = clock.day { date = dateParser.day(day) }
            ownReminder = nil
            result.tokens[index].kind = clock.day == nil ? .time : .date
            if result.reminderOffsetMinutes == nil { result.reminderOffsetMinutes = 0 }
        }

        // A reminder before the due time is relative to it: with no time typed (or set by "in 2 hours") it is
        // plain title text and sets nothing (George, 0.4.1 and again on 0.5.0, brief 41: "A typed reminder like
        // '!15mb' should not highlight before there's a time"). Once a time is typed it lights up and counts.
        // The Reminder chip picked before a time keeps its offset in the draft (`QuickAddDraft`). A reminder
        // from now ("!15m") needs no time (brief 48).
        if time == nil, moment == nil, !dueTimeIsSet {
            result.reminderOffsetMinutes = nil
            let beforeDue = { (token: QuickAddToken) in token.kind == .reminder && ReminderPhrase(token: token.text)?.isBeforeDue == true }
            for token in result.tokens where beforeDue(token) {
                for k in words.indices where token.range.contains(words[k].range.lowerBound) { consumed[k] = false }
            }
            result.tokens.removeAll(where: beforeDue)
        }
        // "Remind me to call mom tomorrow at 5": with a time and no other reminder typed, at the time (brief 175).
        if remindMeTo, time != nil || moment != nil, result.reminderOffsetMinutes == nil, ownReminder == nil {
            result.reminderOffsetMinutes = 0
        }
        if case .span(let span)? = ownReminder { result.reminderFromNow = span }

        // Title = whatever was not consumed or was superseded, with surrounding quotes stripped. A word just before a
        // phrase loses a trailing ",", ";", ":" or dash, and a dash on its own goes: they joined the phrase to the
        // sentence ("Stir the soup, reminder in 15 minutes", "Call mom - remind me at 4"; the second review of brief 175).
        var titleWords: [String] = []
        for (k, word) in words.enumerated() where !consumed[k] || supersededWords.contains(k) {
            var t = word.text
            if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") { t = String(t.dropFirst().dropLast()) }
            if k + 1 < words.count, consumed[k + 1], !supersededWords.contains(k + 1) {
                while let last = t.last, ",;:-–—".contains(last) { t.removeLast() }
                if t.isEmpty { continue }
            }
            titleWords.append(t)
        }
        result.title = titleWords.joined(separator: " ")
        // "Remind me to call mom" is "Call mom": a reminder said in words that opens the text, and still stands, leaves
        // the rest of the title starting with a capital (brief 175); so does one that became the due time.
        if let spokenStart, result.tokens.contains(where: { !$0.isSuperseded && $0.range.lowerBound == spokenStart }),
           let first = result.title.first {
            result.title = first.uppercased() + result.title.dropFirst()
        }
        // A lead kept as the title starts with a capital too: "reminder in 2 hours" is "Reminder".
        if leadIsTitle, let first = result.title.first { result.title = first.uppercased() + result.title.dropFirst() }

        // Resolve date/time. A date the user typed is kept as typed, even in the past ("yesterday").
        let dateWasTyped = date != nil
        let hasDay = dateWasTyped || result.recurrence != nil || dueDayIsSet
        if timeIsOpen, let typed = time { time = (hour(typed.0, typed.1, words: lowers, hasDay: hasDay), typed.1) }
        if date == nil, let rule = result.recurrence {
            date = rule.firstOccurrence(onOrAfter: dateParser.today, calendar: dateParser.calendar)
        } else if dateIsStart, let start = date, let rule = result.recurrence {
            // "every monday starting nov 24" (a Tuesday) starts on the Monday after; "every month on the
            // 28th starting dec 1" on Dec 28. A day typed without "starting" is kept as typed.
            date = rule.firstOccurrence(onOrAfter: start, calendar: dateParser.calendar)
        }
        if let time {
            var candidate = dateParser.date(date ?? dateParser.today, hour: time.0, minute: time.1)
            if !dateWasTyped, candidate < dateParser.now {
                if let rule = result.recurrence {
                    // Typed after today's time: the rule's next occurrence ("every weekday 9am" at 2 pm is
                    // tomorrow 9 am). Anchor first so "every month" from the 31st keeps the 31st.
                    let anchored = rule.anchored(to: candidate, calendar: dateParser.calendar)
                    result.recurrence = anchored
                    candidate = anchored.nextOccurrence(after: candidate, calendar: dateParser.calendar)
                } else {
                    candidate = dateParser.date(dateParser.day(1), hour: time.0, minute: time.1)
                }
            }
            result.dueDate = candidate
            result.hasDueTime = true
        } else if let moment {
            result.dueDate = moment
            result.hasDueTime = true
        } else if let date {
            result.dueDate = date
            result.hasDueTime = false
        }
        // "every month" keeps the day it starts on (the 31st stays the 31st after a short month), and a
        // timed repeat its time.
        if let rule = result.recurrence, let due = result.dueDate {
            result.recurrence = rule.anchored(to: due, calendar: dateParser.calendar)
                .timed(to: due, hasTime: result.hasDueTime, calendar: dateParser.calendar)
        }
        // The task's own reminder moment, once its due day is known (a clock time goes off on that day, brief 175).
        switch ownReminder {
        case .span(let span)?:
            result.reminderDate = span.date(from: dateParser.now, calendar: dateParser.calendar)
        case .clock(var clock, let open)?:
            if open { clock.hour = hour(clock.hour, clock.minute, words: lowers, hasDay: hasDay || clock.day != nil) }
            result.reminderClock = clock
            result.reminderDate = clock.date(dueDay: result.dueDate, now: dateParser.now, calendar: dateParser.calendar)
        case nil:
            break
        }
        result.tokens.sort { $0.range.lowerBound < $1.range.lowerBound }
        return result
    }

    /// Where a winning token is kept: one per kind, but two for reminders: the task's own moment (from now, or a clock
    /// time) and one before its due time.
    enum Slot: Hashable {
        case kind(QuickAddToken.Kind)
        case reminderFromNow, reminderBeforeDue
    }

    /// The task's own reminder moment as typed. `open`: the clock is "at 1" to "at 11" with no am or pm, its hour as
    /// typed (`hour(_:_:words:hasDay:)`).
    enum OwnReminder {
        case span(ReminderSpan)
        case clock(ReminderClock, open: Bool)
    }

    /// The hour "at 1" to "at 11" with no am or pm stands for (`hour` as typed), a due time's or a reminder clock's:
    /// what decides is in the rest of the text (brief 175; the supervisor's decisions on its two reviews).
    /// - A morning cue among the words (wake, waking, wake up, get up, breakfast, sunrise, dawn, early, morning): as
    ///   typed ("Wake up at 6 tomorrow", "Breakfast at 6:30", "Early flight at 6", "Meditate every morning at 6").
    /// - An evening cue (night, tonight, evening, dinner, supper): 5 to 11 the evening ("Game night at 6", "Dinner at 8",
    ///   "Remind me tonight at 9"); 1 to 4 as typed with "night" ("Take pills every night at 1"), else the afternoon
    ///   ("Dinner at 4").
    /// - No cue: 7 to 11 as typed. 1 to 6 beside a day (`hasDay`: typed, a repeat's, the task's own) the afternoon
    ///   ("tomorrow at 5"); with no day, 1 to 4 the afternoon, today's while it is still ahead and else tomorrow's
    ///   ("Lunch at 1"), and 5 or 6 the next one to come, as they can mean early morning: "at 6" is 6 pm at 2 pm, 6 am
    ///   tomorrow at 10 pm, 6 am today at 5 am.
    func hour(_ hour: Int, _ minute: Int, words: [String], hasDay: Bool) -> Int {
        let cues = DayHalfCues(words)
        if cues.morning { return hour }
        if cues.evening { return hour >= 5 || !cues.night ? hour + 12 : hour }
        guard hour <= 6 else { return hour }
        if hasDay || hour <= 4 { return hour + 12 }
        let today = dateParser.today, now = dateParser.now
        if dateParser.date(today, hour: hour, minute: minute) >= now { return hour }
        return dateParser.date(today, hour: hour + 12, minute: minute) >= now ? hour + 12 : hour
    }

    /// The words in a text that say which half of the day an open hour is (`hour(_:_:words:hasDay:)`), as words: "Nightly"
    /// is none, nor "#Dinner".
    struct DayHalfCues {
        var morning = false
        var evening = false
        /// "night" itself, with which 1 to 4 stay in the small hours.
        var night = false

        init(_ words: [String]) {
            let plain = words.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?\"'()")) }
            let mornings: Set<String> = ["wake", "wakes", "waking", "woke", "breakfast", "sunrise", "dawn", "early", "morning",
                                         "mornings"]
            let evenings: Set<String> = ["night", "nights", "tonight", "evening", "evenings", "dinner", "supper"]
            for (k, word) in plain.enumerated() {
                if mornings.contains(word) { morning = true }
                // "get up", "gets up", "getting up"
                if ["get", "gets", "getting"].contains(word), k + 1 < plain.count, plain[k + 1] == "up" { morning = true }
                if evenings.contains(word) { evening = true }
                if word == "night" || word == "nights" { night = true }
            }
        }
    }

    static func priority(from w: String) -> Priority? {
        var s = w
        if s.hasPrefix("!!") { s = "p" + s.dropFirst(2) }
        guard s.count == 2, s.hasPrefix("p"), let n = Int(String(s.last!)) else { return nil }
        return Priority(rawValue: n)
    }

    /// "priority 1" to "priority 4", "priority one" to "priority four" (brief 175): as "p1" to "p4" are. The parser reads
    /// them only where they end the words (`endsTheWords`).
    static func spokenPriority(_ words: [String], at i: Int) -> Priority? {
        guard i + 1 < words.count, DateExpressionParser.normalize(words[i]) == "priority" else { return nil }
        let levels = ["1": 1, "2": 2, "3": 3, "4": 4, "one": 1, "two": 2, "three": 3, "four": 4]
        let level = words[i + 1].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))
        return levels[level].flatMap(Priority.init(rawValue:))
    }

    /// Words said to the app end at `words[k]` rather than run on as part of a sentence (the review of brief 175): `k`
    /// is the end of the text, the word before it ends in punctuation, or a dash or another phrase starts there. "Fix
    /// sink priority 1", "… priority 1, then paint", "… priority 1 tomorrow"; not "Fix priority 1 bugs".
    func endsTheWords(_ words: [String], at k: Int) -> Bool {
        guard k < words.count else { return true }
        if ReminderPhrase.endsClause(words[k - 1]) || ["-", "–", "—"].contains(words[k]) { return true }
        return startsPhrase(words, at: k)
    }

    /// A phrase the parser reads starts at `words[k]`: a "!" word, a priority, a group, a label, a reminder, a repeat,
    /// a date or a time.
    func startsPhrase(_ words: [String], at k: Int) -> Bool {
        guard k < words.count else { return false }
        let w = words[k]
        if w.hasPrefix("!") || Self.priority(from: w) != nil { return true }
        if (w.hasPrefix("#") || w.hasPrefix("@")) && w.count > 1 { return true }
        if ReminderPhrase.reading(words, at: k, afterPhrase: true) != nil || Self.matchRecurrence(words, at: k) != nil {
            return true
        }
        if dateParser.matchRelativeTime(in: words, at: k) != nil || dateParser.matchTime(in: words, at: k) != nil { return true }
        return matchDateOrStart(words, at: k) != nil
    }

    /// The text opens with "Remind me to" (any case; brief 175).
    static func opensWithRemindMeTo(_ words: [String], at k: Int = 0) -> Bool {
        guard words.count >= k + 3 else { return false }
        return words[k..<(k + 3)].map(DateExpressionParser.normalize) == ["remind", "me", "to"]
    }

    /// Resolves a `#`/`@`-prefixed name. Supports quoted names and multi-word known names.
    func matchName(words: [Word], at i: Int, prefix: Character, known: [String]) -> (String, Int) {
        var raw = String(words[i].text.dropFirst())
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            raw = String(raw.dropFirst().dropLast())
            return (canonical(raw, in: known) ?? raw, 1)
        }
        // Try the longest known multi-word name starting with this word.
        var best: (String, Int)? = nil
        for name in known {
            let parts = name.split(separator: " ").map { $0.lowercased() }
            guard parts.count > 1, i + parts.count <= words.count else { continue }
            var ok = parts[0] == raw.lowercased()
            if ok {
                for k in 1..<parts.count where words[i + k].lower != parts[k] { ok = false; break }
            }
            if ok, best == nil || parts.count > best!.1 { best = (name, parts.count) }
        }
        if let best { return best }
        return (canonical(raw, in: known) ?? raw, 1)
    }

    func canonical(_ name: String, in known: [String]) -> String? {
        known.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func matchRecurrence(_ words: [String], at i: Int) -> (RecurrenceRule, Int)? {
        // "every month on the 28th", "every first Monday", "every year on Mar 3" (QuickAddParser+Repeats)
        if let placed = matchPlacedRepeat(words, at: i) { return placed }
        // "tue thu sat", "every mon, wed & fri", "every 2 weeks on tue and thu" (QuickAddParser+Weekdays)
        if let days = matchWeekdayRepeat(words, at: i) { return days }
        let w = DateExpressionParser.normalize(words[i])
        switch w {
        case "daily": return (.daily, 1)
        case "weekly": return (.weekly, 1)
        case "monthly": return (.monthly, 1)
        case "yearly", "annually": return (.yearly, 1)
        case "every": break
        default: return nil
        }
        guard i + 1 < words.count else { return nil }
        let n = DateExpressionParser.normalize(words[i + 1])
        switch n {
        case "day": return (.daily, 2)
        case "week": return (.weekly, 2)
        case "month": return (.monthly, 2)
        case "year": return (.yearly, 2)
        case "weekday", "weekdays", "workday", "workdays": return (.weekdays, 2)
        case "weekend", "weekends": return (RecurrenceRule(frequency: .weekly, weekdays: [1, 7]), 2)
        case "morning", "night", "evening": return (.daily, 2)
        case "other":
            guard i + 2 < words.count else { return nil }
            switch DateExpressionParser.normalize(words[i + 2]) {
            case "day": return (RecurrenceRule(frequency: .daily, interval: 2), 3)
            case "week": return (RecurrenceRule(frequency: .weekly, interval: 2), 3)
            case "month": return (RecurrenceRule(frequency: .monthly, interval: 2), 3)
            case "year": return (RecurrenceRule(frequency: .yearly, interval: 2), 3)
            default: return nil
            }
        default: break
        }
        // every N days/weeks/months/years (an absurd N stays in the title)
        if let count = Int(n), (1...RecurrenceRule.maxInterval).contains(count), i + 2 < words.count,
           let unit = DateExpressionParser.unitDays(words[i + 2]) {
            let freq: RecurrenceRule.Frequency
            switch unit.component {
            case .day: freq = .daily
            case .weekOfYear: freq = .weekly
            case .month: freq = .monthly
            default: freq = .yearly
            }
            return (RecurrenceRule(frequency: freq, interval: count), 3)
        }
        return nil
    }
}

/// A typed reminder. The codes (brief 48): `!15m`, `!2h`, `!1d`, `!90m`, `!1h30m`, `!1d12h` = that long from now;
/// the same with a "b" (`!15mb`, `!1hb`, `!1h30mb`) = that long before the due time; `!0` and `!at` = at the
/// due time, and so is zero before it (`!0mb`, `!0hb`, `!0db`, `!0b`, brief 127). The parts come in the order
/// d, h, m, each once, each N ≥ 1, four weeks at most in all. No other single word is a code (`!`, `!0m`, `!m`,
/// `!15`, `!30m15h`, `!29d`, `!0h30mb`).
///
/// And in words (brief 175, `QuickAddParser+Reminders`): `!At time of task`, `!10 minutes before`, `!In 5 minutes`,
/// a clock time (`!4pm`, `!4:00 PM`), or "remind me" before the same words without the "!"; "reminder" alone takes
/// only the relative ones (before, in, at the time), never a clock time or a day.
public enum ReminderPhrase: Equatable, Sendable {
    case fromNow(ReminderSpan)
    /// 0 is at the due time.
    case beforeDue(minutes: Int)
    /// At a clock time: a moment of the task's own, as a "from now" reminder is (`ReminderClock.date`).
    case at(ReminderClock)

    public var isBeforeDue: Bool {
        if case .beforeDue = self { return true }
        return false
    }

    /// The phrase a reminder token's words stand for, one word or several ("!15m", "!10 minutes before", "remind me in
    /// an hour", "Remind me in 30 minutes to"; case and trailing ",.;" ignored), or nil if they aren't one.
    public init?(token text: String) {
        let words = text.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        // A dictated lead-in opens it too: "Can you remind me in 10 minutes to".
        let lead = Self.leadIn(words, at: 0)
        if let (phrase, n) = Self.match(words, at: lead, atStart: true), lead + n == words.count {
            self = phrase
            return
        }
        // A phrase said in words whose lead went to the title (a text of only the phrase: "Remind me in 10 minutes" is
        // the title "Remind me" and the token "in 10 minutes"; the second review of brief 175).
        guard let words0 = words.first, !words0.hasPrefix("!"),
              let reading = Self.matchBody(words, at: 0, trailingDay: true), reading.length == words.count else { return nil }
        if reading.openHour, case .at(var clock) = reading.phrase, (1...6).contains(clock.hour) {
            clock.hour += 12
            self = .at(clock)
        } else {
            self = reading.phrase
        }
    }

    /// The phrase a one-word `!…` code stands for (case and trailing ",.;" ignored), or nil if it isn't one.
    init?(code word: String) {
        var w = Substring(DateExpressionParser.normalize(word))
        guard w.hasPrefix("!"), !w.hasPrefix("!!") else { return nil }
        w.removeFirst()
        // Zero before the due time is at it (brief 127): "!0mb", "!0hb", "!0db" and "!0b" read as "!0" does.
        if ["0", "at", "0b", "0mb", "0hb", "0db"].contains(w) { self = .beforeDue(minutes: 0); return }
        let before = w.hasSuffix("b")
        if before { w.removeLast() }
        guard let span = ReminderSpan(parts: w) else { return nil }
        self = before ? .beforeDue(minutes: span.totalMinutes) : .fromNow(span)
    }
}

/// How long a reminder phrase reaches: whole days (each the same clock time on the next day, so `!1d` keeps
/// 9:00 across a daylight-saving change) and minutes (real time: `!1h` is always 60 minutes on).
public struct ReminderSpan: Hashable, Codable, Sendable {
    public var days: Int
    public var minutes: Int

    public init(days: Int = 0, minutes: Int = 0) {
        self.days = days
        self.minutes = minutes
    }

    public var totalMinutes: Int { days * 24 * 60 + minutes }

    /// "1d12h30m" (no "!"): parts in the order d, h, m, each once, each a whole number ≥ 1. Nil for anything
    /// else, or longer than `ReminderOffset.maxMinutes`. Overflow-checked: it runs on every keystroke.
    init?(parts: Substring) {
        var days = 0, minutes = 0, lastUnit = -1, digits = ""
        for c in parts {
            if c.isASCII, c.isNumber { digits.append(c); continue }
            let unit: Int, scale: Int
            switch c {
            case "d": unit = 0; scale = 24 * 60
            case "h": unit = 1; scale = 60
            case "m": unit = 2; scale = 1
            default: return nil
            }
            guard unit > lastUnit, let n = Int(digits), n > 0 else { return nil }
            let (value, overflow) = n.multipliedReportingOverflow(by: scale)
            guard !overflow, value <= ReminderOffset.maxMinutes else { return nil }
            if unit == 0 { days = n } else { minutes += value }
            lastUnit = unit
            digits = ""
        }
        guard digits.isEmpty, lastUnit >= 0 else { return nil }
        self.init(days: days, minutes: minutes)
        guard totalMinutes <= ReminderOffset.maxMinutes else { return nil }
    }

    /// `now` plus the span: the days on the calendar, then the minutes in real time.
    public func date(from now: Date, calendar: Calendar = .current) -> Date {
        let day = days == 0 ? now : calendar.date(byAdding: .day, value: days, to: now) ?? now.addingTimeInterval(TimeInterval(days * 86_400))
        return day.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// "15 min", "1 hour", "1 hr 30 min", "1 day", "2 days 1 hr".
    public var text: String { ReminderOffset.duration(minutes: totalMinutes) }

    /// The token a chip writes: "!15m", "!1h", "!90m", "!1d", "!1d30m".
    public var token: String {
        var out = "!"
        if days > 0 { out += "\(days)d" }
        if minutes > 0 { out += minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m" }
        return out
    }
}

/// The before-the-due-time half of the reminder grammar (`ReminderPhrase.beforeDue`), shared by the parser,
/// the chips and the notification copy. The parser reads one only when the task has a due time; without one
/// it is title text (`QuickAddParser.parse`).
public enum ReminderOffset {
    /// The longest offset accepted: four weeks.
    public static let maxMinutes = 28 * 24 * 60

    /// The offset in minutes a `!…mb` / `!…hb` / `!…db` / `!0` / `!at` word stands for, or nil if it isn't
    /// one (`!15m` is 15 minutes from now, not an offset).
    public static func minutes(fromToken word: String) -> Int? {
        guard case .beforeDue(let minutes)? = ReminderPhrase(token: word) else { return nil }
        return minutes
    }

    /// The token a chip writes: "!15mb", "!1hb", "!1db"; "!at" for zero.
    public static func token(minutes: Int) -> String {
        guard minutes > 0 else { return "!at" }
        if minutes % (24 * 60) == 0 { return "!\(minutes / (24 * 60))db" }
        if minutes % 60 == 0 { return "!\(minutes / 60)hb" }
        return "!\(minutes)mb"
    }

    /// "15 min", "1 hour", "2 hours", "1 day", "1 hr 30 min".
    public static func duration(minutes: Int) -> String {
        let day = 24 * 60
        let days = minutes / day, hours = (minutes % day) / 60, mins = minutes % 60
        if minutes > 0, minutes % day == 0 { return days == 1 ? "1 day" : "\(days) days" }
        if days == 0, hours > 0, mins == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append("\(hours) hr") }
        if mins > 0 || parts.isEmpty { parts.append("\(mins) min") }
        return parts.joined(separator: " ")
    }

    /// The chip's wording: "15 min before"; "At time" for zero.
    public static func label(minutes: Int) -> String {
        minutes > 0 ? duration(minutes: minutes) + " before" : "At time"
    }
}
