/// Numbers a model's loads, so only the newest one shows what it read.
///
/// A screen loads from `.task`, and again when a pushed screen closes, after Undo, or on Try
/// again. Those loads overlap, and the older one can finish last with data from before the
/// change. Each load takes a number when it starts and only shows its result while it's still
/// the newest. Your looks' run counter (Phase 10b) works the same way.
struct LoadGeneration {
    private var latest = 0

    /// Starts a load and returns its number.
    mutating func begin() -> Int {
        latest += 1
        return latest
    }

    /// True while `load` is the newest load.
    func isCurrent(_ load: Int) -> Bool {
        load == latest
    }
}
