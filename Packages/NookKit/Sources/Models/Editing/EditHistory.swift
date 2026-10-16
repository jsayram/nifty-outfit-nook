import Foundation

/// Undo and Redo for hand changes to a look: a swap or a removal on Your looks (LR-08.2), and
/// each change in Make your own look (PRD §7.3).
///
/// It keeps whole values, not steps, so Undo gives back exactly the earlier look. At most
/// `limit` changes are kept (PRD §7.3 asks for up to 20); the oldest go first. A new change
/// clears Redo.
public struct EditHistory<Value: Hashable & Sendable>: Hashable, Sendable {
    /// How many changes Undo can go back through.
    public static var limit: Int { 20 }

    /// Earlier values, oldest first. The last one is what Undo gives back.
    public private(set) var undoStack: [Value] = []
    /// Values Undo stepped back from, most recent last.
    public private(set) var redoStack: [Value] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Records the value as it was before a change.
    public mutating func record(_ before: Value) {
        undoStack.append(before)
        if undoStack.count > Self.limit {
            undoStack.removeFirst(undoStack.count - Self.limit)
        }
        redoStack.removeAll()
    }

    /// Steps back: returns the earlier value and keeps `current` for Redo. `nil` when there's
    /// nothing to undo.
    public mutating func undo(from current: Value) -> Value? {
        guard let earlier = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return earlier
    }

    /// Steps forward again after Undo. `nil` when there's nothing to redo.
    public mutating func redo(from current: Value) -> Value? {
        guard let later = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return later
    }

    /// Forgets every change, for a new look.
    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
