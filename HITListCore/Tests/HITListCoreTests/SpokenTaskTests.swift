import XCTest
@testable import HITListCore

/// What a capture said to the Stream ring (or a phrase Siri heard) becomes before the quick-add parser reads it
/// (brief 176).
final class SpokenTaskTests: XCTestCase {
    func testASentenceBecomesTheCardsWords() {
        XCTAssertEqual(SpokenTask.text(from: "Call the dentist tomorrow at 9am p2."), "Call the dentist tomorrow at 9am p2")
        XCTAssertEqual(SpokenTask.text(from: "  buy milk!  "), "Buy milk")
        XCTAssertEqual(SpokenTask.text(from: "Ask Sam about the trip?"), "Ask Sam about the trip?", "a question keeps its mark")
        XCTAssertEqual(SpokenTask.text(from: "Wait..."), "Wait..", "one trailing mark only")
        XCTAssertEqual(SpokenTask.text(from: "iPhone case for Sam."), "iPhone case for Sam", "a word with capitals of its own")
        XCTAssertEqual(SpokenTask.text(from: "3 eggs"), "3 eggs")
        XCTAssertEqual(SpokenTask.text(from: "élan vital"), "Élan vital")
    }

    func testOneLeadingWordForTheListIsDropped() {
        let cases = [
            "Task: call mom": "Call mom",
            "task, call mom": "Call mom",
            "Task - call mom": "Call mom",
            "Task – call mom": "Call mom",
            "To do: buy milk": "Buy milk",
            "To-do: buy milk": "Buy milk",
            "Todo, buy milk": "Buy milk",
            "New task: water the plants friday": "Water the plants friday",
            "Add: bread #Errands": "Bread #Errands",
            "HITList: book flights p1": "Book flights p1",
            "Hit list, book flights": "Book flights",
            "Hitlist - book flights": "Book flights",
            "Task : spaced out": "Spaced out",
        ]
        for (capture, expected) in cases {
            XCTAssertEqual(SpokenTask.text(from: capture), expected, capture)
        }
    }

    func testWordsThatOnlyLookLikeALeadStay() {
        XCTAssertEqual(SpokenTask.text(from: "Add milk to the list"), "Add milk to the list", "no mark after it")
        XCTAssertEqual(SpokenTask.text(from: "Add-on for the car"), "Add-on for the car", "a hyphen inside a word")
        XCTAssertEqual(SpokenTask.text(from: "Tasks: sort them"), "Tasks: sort them")
        XCTAssertEqual(SpokenTask.text(from: "Address: 1 Main St"), "Address: 1 Main St")
        XCTAssertEqual(SpokenTask.text(from: "Task call mom"), "Task call mom", "without the rule, a mark is needed")
        XCTAssertEqual(SpokenTask.text(from: "Task: to do: twice"), "To do: twice", "one lead only")
    }

    func testNothingLeftIsNil() {
        for capture in ["", "   ", ".", "!", "Task:", "Todo - ", "Task: ."] {
            XCTAssertNil(SpokenTask.text(from: capture), "“\(capture)”")
        }
    }

    func testTheStartsWithTaskRule() {
        XCTAssertTrue(SpokenTask.startsWithTask("Task: call mom"))
        XCTAssertTrue(SpokenTask.startsWithTask("task, call mom"))
        XCTAssertTrue(SpokenTask.startsWithTask("Task. Call mom."))
        XCTAssertTrue(SpokenTask.startsWithTask("Task call mom"))
        XCTAssertTrue(SpokenTask.startsWithTask("  TASK — call mom"))
        XCTAssertFalse(SpokenTask.startsWithTask("Tasks for today"))
        XCTAssertFalse(SpokenTask.startsWithTask("Taskbar is broken"))
        XCTAssertFalse(SpokenTask.startsWithTask("Task's done"))
        XCTAssertFalse(SpokenTask.startsWithTask("Remember where I parked"))
        XCTAssertFalse(SpokenTask.startsWithTask("New task: buy milk"), "the switch says “Task”")

        XCTAssertEqual(SpokenTask.text(from: "Task. Call the dentist tomorrow at 9am.", onlyStartingWithTask: true),
                       "Call the dentist tomorrow at 9am")
        XCTAssertEqual(SpokenTask.text(from: "Task call mom", onlyStartingWithTask: true), "Call mom")
        XCTAssertEqual(SpokenTask.text(from: "task: buy milk!", onlyStartingWithTask: true), "Buy milk")
        XCTAssertNil(SpokenTask.text(from: "Remember where I parked", onlyStartingWithTask: true), "left in Stream")
        XCTAssertNil(SpokenTask.text(from: "Task", onlyStartingWithTask: true), "nothing left")
        XCTAssertEqual(SpokenTask.text(from: "Remember where I parked", onlyStartingWithTask: false), "Remember where I parked")
    }
}
