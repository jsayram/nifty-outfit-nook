import Models
import Testing

struct EditHistoryTests {
    @Test func undoGivesBackTheEarlierValueAndRedoTheLaterOne() {
        var history = EditHistory<String>()
        #expect(!history.canUndo)
        history.record("a")
        history.record("b")
        #expect(history.undo(from: "c") == "b")
        #expect(history.undo(from: "b") == "a")
        #expect(history.undo(from: "a") == nil)
        #expect(history.redo(from: "a") == "b")
        #expect(history.redo(from: "b") == "c")
        #expect(history.redo(from: "c") == nil)
    }

    @Test func aNewChangeClearsRedo() {
        var history = EditHistory<Int>()
        history.record(1)
        _ = history.undo(from: 2)
        #expect(history.canRedo)
        history.record(1)
        #expect(!history.canRedo)
    }

    /// PRD §7.3: up to 20 changes; the oldest go first.
    @Test func keepsAtMostTwentyChanges() {
        var history = EditHistory<Int>()
        for value in 0..<25 { history.record(value) }
        #expect(history.undoStack == Array(5..<25))
        var current = 25
        var steps = 0
        while let earlier = history.undo(from: current) {
            current = earlier
            steps += 1
        }
        #expect(steps == 20)
        #expect(current == 5)
    }

    @Test func clearForgetsEverything() {
        var history = EditHistory<Int>()
        history.record(1)
        _ = history.undo(from: 2)
        history.record(3)
        history.clear()
        #expect(!history.canUndo && !history.canRedo)
    }
}
