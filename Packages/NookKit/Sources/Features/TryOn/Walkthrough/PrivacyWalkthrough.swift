import Foundation
import Models
import Observation

/// 33c: the first-time privacy walkthrough, a 5 to 6 second story of what happens to her photo. It
/// is drawn, not filmed: a drawn figure, never a photo of anyone, so nothing of hers is on screen
/// and nothing needs hiding in the app switcher.
///
/// The beats follow the real pipeline in order, and a test checks that every real step
/// (`TryOnStage`) is covered once and in order. A soft privacy veil covers the head and hair
/// (the grey shape the phone paints), the room becomes the studio backdrop, the check that no
/// face is left, the faceless photo goes out, comes back dressed, and her own face fades back on
/// the phone. No head is ever cut off.
enum WalkthroughBeat: Int, CaseIterable, Hashable {
    case yourPhoto
    case veil
    case backdrop
    case checked
    case sent
    case dressed
    case faceBack

    /// How long the beat holds, in seconds. They add up to 5.8.
    var seconds: Double {
        switch self {
        case .yourPhoto: 0.6
        case .veil: 0.9
        case .backdrop: 0.8
        case .checked: 0.7
        case .sent: 1.0
        case .dressed: 0.8
        case .faceBack: 1.0
        }
    }

    /// The real step this beat shows. `nil` for the opening.
    var stage: TryOnStage? {
        switch self {
        case .yourPhoto: nil
        case .veil: .hidingFace
        case .backdrop: .studioBackdrop
        case .checked: .checkingFace
        case .sent, .dressed: .dressing
        case .faceBack: .restoring
        }
    }

    static var totalSeconds: Double { allCases.reduce(0) { $0 + $1.seconds } }

    /// What is drawn at the end of the beat.
    var frame: WalkthroughFrame {
        switch self {
        case .yourPhoto: WalkthroughFrame()
        case .veil: WalkthroughFrame(veiled: true)
        case .backdrop: WalkthroughFrame(veiled: true, studio: true)
        case .checked: WalkthroughFrame(veiled: true, studio: true, checked: true)
        case .sent: WalkthroughFrame(veiled: true, studio: true, checked: true, inCloud: true)
        case .dressed: WalkthroughFrame(veiled: true, studio: true, checked: true, dressed: true)
        case .faceBack: WalkthroughFrame(studio: true, dressed: true, lock: true)
        }
    }
}

/// What the drawing shows at one beat. Reduce Motion draws the same frames and fades between them,
/// so nothing slides or scales.
struct WalkthroughFrame: Equatable {
    /// The soft veil over her head and hair.
    var veiled = false
    /// The plain studio backdrop instead of her room.
    var studio = false
    /// The check that no face is left.
    var checked = false
    /// The faceless photo is out with the image service.
    var inCloud = false
    /// She is wearing the look.
    var dressed = false
    /// "On your phone": her face is back and the lock is shown.
    var lock = false
}

/// Plays the beats one after another on a clock, so tests can run it without waiting. It can be
/// skipped only when `canSkip` (a replay, never the first showing).
@MainActor
@Observable
final class PrivacyWalkthroughModel {
    private(set) var beat: WalkthroughBeat
    private(set) var isFinished = false
    let canSkip: Bool

    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var skipped = false
    @ObservationIgnored private var playing: Task<Void, Never>?

    /// - Parameter beat: where it starts. Only snapshot tests start anywhere but the first beat.
    init(canSkip: Bool, beat: WalkthroughBeat = .yourPhoto, clock: any Clock<Duration> = ContinuousClock()) {
        self.canSkip = canSkip
        self.beat = beat
        self.clock = clock
    }

    /// Plays every beat. True when it ran to the end, false when it was skipped or the screen went
    /// away first.
    func play() async -> Bool {
        for next in WalkthroughBeat.allCases {
            if skipped || Task.isCancelled { return false }
            beat = next
            do {
                try await clock.sleep(for: .seconds(next.seconds))
            } catch {
                return false
            }
        }
        isFinished = true
        return !skipped
    }

    /// Ends the walkthrough now. Does nothing on the first showing.
    func skip() {
        guard canSkip else { return }
        skipped = true
        isFinished = true
    }
}

/// The walkthrough's words.
nonisolated enum WalkthroughText {
    static func caption(_ beat: WalkthroughBeat) -> String {
        switch beat {
        case .yourPhoto:
            String(
                localized: "This is your photo. It starts on your iPhone.", bundle: .module,
                comment: "Privacy walkthrough, beat 1 (33c)")
        case .veil:
            String(
                localized: "Your iPhone covers your head and hair.", bundle: .module,
                comment: "Privacy walkthrough, beat 2 (33c)")
        case .backdrop:
            String(
                localized: "It swaps your room for a plain studio backdrop.", bundle: .module,
                comment: "Privacy walkthrough, beat 3 (33c)")
        case .checked:
            String(
                localized: "It checks that no face is left. If one is, nothing is sent.", bundle: .module,
                comment: "Privacy walkthrough, beat 4 (33c)")
        case .sent:
            String(
                localized: "Only this photo and your clothing photos are sent.", bundle: .module,
                comment: "Privacy walkthrough, beat 5 (33c)")
        case .dressed:
            String(
                localized: "Your picture comes back with you dressed.", bundle: .module,
                comment: "Privacy walkthrough, beat 6 (33c)")
        case .faceBack:
            String(
                localized: "Your iPhone puts your face back on. It never left your phone.", bundle: .module,
                comment: "Privacy walkthrough, beat 7 (33c)")
        }
    }

    /// What VoiceOver reads for the whole animation, step by step.
    static var spoken: String {
        let steps = WalkthroughBeat.allCases.map(caption).joined(separator: " ")
        return String(
            localized: "How your photo stays private. \(steps)", bundle: .module,
            comment: "VoiceOver: the privacy walkthrough. The argument is its steps, one sentence each.")
    }

    static var lock: String {
        String(localized: "On your phone", bundle: .module, comment: "Privacy walkthrough: under the lock (33c)")
    }

    static var skip: String {
        String(localized: "Skip", bundle: .module, comment: "Privacy walkthrough: ends it early on a replay (33c)")
    }
}
