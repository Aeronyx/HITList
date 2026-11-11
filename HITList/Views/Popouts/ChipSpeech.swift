import HITListCore

/// What VoiceOver says for the quick-add card's and the editor's chips (brief 94): what the chip is, then its value,
/// where the chip shows only the value ("Tomorrow 9:00 AM", "P2", "@errands") or only its name when empty.
enum ChipSpeech {
    static func date(_ text: String?) -> String { "Date: \(text ?? "none")" }
    /// "Priority: P1", as the chip writes it (the UI tests read the P1 in it).
    static func priority(_ priority: Priority) -> String { "Priority: " + (priority == .p4 ? "none" : priority.shortName) }
    static func labels(_ names: [String]) -> String {
        "Labels: " + (names.isEmpty ? "none" : names.joined(separator: ", "))
    }
    static func deadline(_ text: String?) -> String { "Deadline: \(text ?? "none")" }
    static func repeats(_ text: String?) -> String { "Repeat: \(text ?? "none")" }
    static func location(_ name: String?) -> String { "Location: \(name ?? "none")" }
}
