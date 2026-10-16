/// Typed search that waits until she pauses, so a long list isn't filtered on every letter
/// (Closet and Saved Looks). An emptied field applies at once, since there's nothing to wait for.
final class SearchDebouncer {
    /// How long typing has to pause before the search runs.
    let delay: Duration
    private var pending: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    /// Runs `apply` once typing has paused, or at once when `text` is empty. A newer call
    /// replaces one still waiting.
    func schedule(_ text: String, apply: @escaping () -> Void) {
        pending?.cancel()
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            apply()
            return
        }
        let delay = delay
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            apply()
        }
    }

    /// Drops a search still waiting, as Clear and pressing Search do.
    func cancel() {
        pending?.cancel()
    }

    /// Waits for a search still waiting to run. For tests.
    func settle() async {
        await pending?.value
    }
}
