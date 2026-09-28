/// A linear undo/redo stack over value snapshots.
///
/// Because a `Recipe` is a small value type, undo is just "remember the previous
/// value" — no command objects or inverse operations needed.
public struct History<Value: Equatable & Sendable>: Sendable {
    public private(set) var current: Value
    private var undoStack: [Value] = []
    private var redoStack: [Value] = []
    private let limit: Int

    public init(_ initial: Value, limit: Int = 100) {
        precondition(limit > 0, "History limit must be positive")
        self.current = initial
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Commits a new value. No-op when the value didn't change, so a slider that
    /// ends where it started doesn't create an empty undo step.
    public mutating func commit(_ value: Value) {
        guard value != current else { return }
        undoStack.append(current)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
        current = value
    }

    @discardableResult
    public mutating func undo() -> Value? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        current = previous
        return previous
    }

    @discardableResult
    public mutating func redo() -> Value? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        current = next
        return next
    }
}
