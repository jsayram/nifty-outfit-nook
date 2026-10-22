import Foundation
import Models
import Observation

/// The try-on camera screen's state (Phase 33b): starts the camera, turns each frame's
/// `FramingObservation` into steady advice (`FramingGuidance`, `FramingCoach`), and takes the
/// photo, by itself after a short countdown once the framing has been good for a moment, or when she
/// taps the shutter. The coach and the rules are plain values in `Models`, tested without a camera.
/// Called with the photo's bytes the moment it's taken.
typealias PhotoTaken = @MainActor @Sendable (Data) -> Void

@MainActor
@Observable
final class TryOnCaptureModel {
    enum Phase: Equatable {
        case starting
        case running
        /// The camera couldn't start.
        case unavailable
        case taking
        /// The shutter failed. She can try again.
        case failed
    }

    private(set) var phase: Phase
    private(set) var coach = FramingCoach()
    /// True when nothing is looking at the frames (or Vision can't), so the hints can't help.
    private(set) var guidanceIsOff: Bool
    /// Take the photo when the framing is good. She can turn it off and use the shutter.
    var takesItself = true {
        didSet {
            if takesItself != oldValue { coach.reset() }
        }
    }

    let source: any TryOnFrameSource
    private let now: () -> Date
    private var misses = 0
    /// Frames in a row that couldn't be looked at before the hints say they're off.
    static let missesBeforeOff = 6
    /// How often the countdown is moved on.
    static let tickInterval = Duration.milliseconds(250)

    init(source: any TryOnFrameSource, phase: Phase = .starting, now: @escaping () -> Date = { .now }) {
        self.source = source
        self.phase = phase
        self.now = now
        guidanceIsOff = !source.givesGuidance
    }

    /// What to say now.
    var advice: FramingAdvice { coach.advice }

    /// Starts the camera and follows it until the screen goes away.
    func run(photoTaken: @escaping PhotoTaken) async {
        guard await source.start() else {
            phase = .unavailable
            return
        }
        phase = .running
        guard source.givesGuidance else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.listen() }
            group.addTask { await self.keepTime(photoTaken: photoTaken) }
            await group.waitForAll()
        }
    }

    func stop() {
        source.stop()
    }

    private func listen() async {
        for await seen in source.observations {
            receive(seen, at: now())
        }
    }

    private func keepTime(photoTaken: @escaping PhotoTaken) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.tickInterval)
            if tick(at: now()) { await take(photoTaken) }
        }
    }

    /// One frame's result. `nil` is a frame that couldn't be looked at.
    func receive(_ seen: FramingObservation?, at time: Date) {
        guard phase == .running else { return }
        guard let seen else {
            misses += 1
            if misses >= Self.missesBeforeOff { guidanceIsOff = true }
            return
        }
        misses = 0
        guidanceIsOff = false
        coach.observe(FramingGuidance.advice(for: seen), at: time)
    }

    /// Moves the countdown on. True when the photo should be taken now.
    func tick(at time: Date) -> Bool {
        guard phase == .running, takesItself, !guidanceIsOff else { return false }
        return coach.tick(at: time)
    }

    /// Takes the photo: by itself, or from the shutter.
    func take(_ photoTaken: @escaping PhotoTaken) async {
        guard phase == .running || phase == .failed else { return }
        coach.markTaken()
        phase = .taking
        guard let data = await source.takePhoto() else {
            phase = .failed
            coach.reset()
            return
        }
        source.stop()
        photoTaken(data)
    }
}
