import Foundation

/// The steps of a real try-on picture, in the order the app does them (Phase 33a's pipeline, shown
/// by Phase 33c). Each one is a real boundary in the code, so the loading screen's captions come
/// from the work itself and never from a timer:
///
/// - `hidingFace`: on the phone, finding her outline and face and covering her head and hair.
/// - `studioBackdrop`: on the phone, replacing her room with the plain studio backdrop.
/// - `checkingFace`: on the phone, looking for a face in what would be sent, in the pixels and in
///   the exact JPEG. Any face stops the try-on and nothing is sent.
/// - `dressing`: the faceless photo and the clothing photos go out as one request, the image
///   service dresses her, and the picture comes back. The app can't tell the upload from the
///   dressing (one request, answered when the picture is ready), so they are one step.
/// - `restoring`: on the phone, her own head goes back on.
public enum TryOnStage: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case hidingFace
    case studioBackdrop
    case checkingFace
    case dressing
    case restoring

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Whether the step runs on her iPhone alone (the last one does too, after the picture is back).
    public var isOnThePhone: Bool { self != .dressing }

    /// Whether the step comes before anything is sent. Nothing has left the phone until `dressing`.
    public var isBeforeSending: Bool { self < .dressing }
}

/// Where a try-on picture is, for the loading screen's captions: the step in progress, or the step
/// it stopped at. Built from the phone's own steps (`preparing`) or from the background job (27c).
public struct TryOnProgress: Hashable, Sendable {
    /// How one step looks in the list.
    public enum Mark: Hashable, Sendable {
        case done
        case doing
        /// Waiting for an earlier picture's job to finish, so nothing is sent yet.
        case waiting
        case todo
        /// The step it stopped at.
        case stopped
    }

    /// The step in progress, or where it stopped.
    public let stage: TryOnStage
    /// It stopped at `stage` (a refusal on the phone, or a failed job).
    public let isStopped: Bool
    /// Everything is done.
    public let isFinished: Bool
    /// `dressing` is waiting for the job before it (the server runs one paid action at a time).
    public let isWaiting: Bool
    /// `dressing` is taking longer than the first answer ("still running"); asked again with the
    /// same key until it's done.
    public let isStillGoing: Bool

    private init(
        stage: TryOnStage, isStopped: Bool = false, isFinished: Bool = false, isWaiting: Bool = false,
        isStillGoing: Bool = false
    ) {
        self.stage = stage
        self.isStopped = isStopped
        self.isFinished = isFinished
        self.isWaiting = isWaiting
        self.isStillGoing = isStillGoing
    }

    /// On the phone, before anything is sent.
    public static func preparing(_ stage: TryOnStage) -> TryOnProgress { TryOnProgress(stage: stage) }

    /// It stopped at this step: the phone refused (nothing was sent), or the job failed.
    public static func stopped(at stage: TryOnStage) -> TryOnProgress { TryOnProgress(stage: stage, isStopped: true) }

    /// A try-on job's state. `nil` for any other kind of job.
    public init?(job: AIJob) {
        guard job.kind == .tryOn else { return nil }
        let stage = job.tryOnStage ?? .dressing
        switch job.state {
        case .queued: self = TryOnProgress(stage: .dressing, isWaiting: true)
        case .running: self = TryOnProgress(stage: stage)
        case .stillRunning: self = TryOnProgress(stage: stage, isStillGoing: stage == .dressing)
        case .done: self = TryOnProgress(stage: .restoring, isFinished: true)
        case .failed, .cancelled: self = TryOnProgress(stage: stage, isStopped: true)
        }
    }

    /// What `step` shows.
    public func mark(for step: TryOnStage) -> Mark {
        if isFinished { return .done }
        if step < stage { return .done }
        if step == stage {
            if isStopped { return .stopped }
            return isWaiting ? .waiting : .doing
        }
        return .todo
    }

    /// Nothing has left the phone yet: still preparing, or refused before sending.
    public var nothingSentYet: Bool { stage.isBeforeSending || isWaiting }
}
