import Foundation
import Synchronization

/// The app-level owner of cloud styling requests (Phase 27a; Jose, 21 October 2026: AI work is
/// never tied to a screen). A request she starts keeps running when she leaves Your looks to
/// browse or search, and its looks land in her history (the look store, unsaved, as LR-06 keeps
/// every result) whether or not a screen still waits for them. A screen that comes back, or a
/// new Style me with the same choices ("From your history", FR-58), finds them there.
///
/// Minimal on purpose: a later phase adds a persisted job list, resuming after a relaunch, an
/// in-app "your looks are ready" banner and local notifications.
public final class StylingJobs: Sendable {
    public typealias Job = Task<Result<StyleOutcome, StylistError>, Never>

    private let running = Mutex<[StyleRequest.ID: Job]>([:])

    public init() {}

    /// Starts the request's job, or joins it if it's already running. Only an explicit Cancel
    /// stops it, never a screen going away.
    public func run(_ context: StylingContext, services: NookServices) -> Job {
        let id = context.request.id
        return running.withLock { jobs in
            if let job = jobs[id] { return job }
            let job = Job {
                let result = await Self.style(context, services: services)
                _ = self.running.withLock { $0.removeValue(forKey: id) }
                return result
            }
            jobs[id] = job
            return job
        }
    }

    /// She tapped Cancel: stops the job if it's still running.
    public func cancel(_ id: StyleRequest.ID) {
        running.withLock { $0.removeValue(forKey: id) }?.cancel()
    }

    /// Jobs still running, for tests.
    public var runningCount: Int { running.withLock { $0.count } }

    private static func style(_ context: StylingContext, services: NookServices) async -> Result<
        StyleOutcome, StylistError
    > {
        let outcome: StyleOutcome
        do {
            outcome = try await services.stylist.style(context)
        } catch {
            return .failure(error)
        }
        if let result = outcome.result, !ResultCheck.problems(in: result, for: context).isEmpty {
            return .failure(.notCompleted)
        }
        // Her history, whatever any screen is doing now. Neither failing hides the result.
        for look in outcome.result?.versions ?? [] where !(outcome.result?.notes.contains(.fromHistory) ?? false) {
            try? await services.looks.save(look)
        }
        if let suitcaseID = context.request.source.suitcaseID {
            try? await services.suitcases.markUsed(suitcaseID, at: context.now)
        }
        return .success(outcome)
    }
}
