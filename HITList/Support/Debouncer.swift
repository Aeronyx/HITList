import Foundation

/// Runs the most recently scheduled work once no new work has been scheduled for `delay`.
@MainActor
final class Debouncer {
    private let delay: Duration
    private var pending: Task<Void, Never>?

    init(delay: Duration) { self.delay = delay }

    func schedule(_ work: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            work()
        }
    }
}
