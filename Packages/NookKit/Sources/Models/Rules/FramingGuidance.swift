import CoreGraphics
import CoreVideo
import Foundation

/// What the phone sees in one camera frame, or in a photo she picked, for the try-on photo's
/// guidance (Phase 33b). Everything is a share of the frame, with the origin at the top left, in
/// the upright picture. The values come from Apple Vision's body pose and person segmentation on
/// the phone (`Services`), and from a stand-in in tests; the rules below never touch the camera.
public struct FramingObservation: Sendable, Equatable {
    public enum Joint: Sendable, Hashable, CaseIterable {
        case nose, leftEye, rightEye, neck
        case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
        case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
    }

    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double
        /// 0 to 1: how sure the body tracking is that it found this joint.
        public var confidence: Double

        public init(x: Double, y: Double, confidence: Double = 1) {
            self.x = x
            self.y = y
            self.confidence = confidence
        }
    }

    /// How many people the body tracking found.
    public var people: Int
    public var joints: [Joint: Point]
    /// Where her outline is, from person segmentation, when it found one.
    public var outline: CGRect?
    /// The frame's width over its height, so sideways and up-down distances compare fairly.
    public var aspect: Double
    /// The average brightness of the whole frame, 0 (black) to 1 (white).
    public var frameBrightness: Double
    /// The average brightness inside her outline, when there is one.
    public var subjectBrightness: Double?

    public init(
        people: Int, joints: [Joint: Point] = [:], outline: CGRect? = nil, aspect: Double = 0.75,
        frameBrightness: Double = 0.5, subjectBrightness: Double? = nil
    ) {
        self.people = people
        self.joints = joints
        self.outline = outline
        self.aspect = aspect
        self.frameBrightness = frameBrightness
        self.subjectBrightness = subjectBrightness
    }

    /// A joint, only when it was found with some confidence.
    func joint(_ name: Joint) -> Point? {
        guard let point = joints[name], point.confidence >= FramingGuidance.Limits.jointConfidence else { return nil }
        return point
    }

    /// Her outline, or the box around the joints found when there's no outline.
    var body: CGRect? {
        if let outline { return outline }
        let points = joints.values.filter { $0.confidence >= FramingGuidance.Limits.jointConfidence }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// One thing to tell her about her framing, most urgent first. The words are in `Features`.
public enum FramingAdvice: Sendable, Hashable, CaseIterable {
    /// Before the first frame has been looked at.
    case starting
    case noOneInView
    case moreThanOne
    /// Part of her is cut off, or too close to an edge.
    case stepBack
    case stepCloser
    case center
    case faceTheCamera
    case armsOut
    case moreLight
    /// The light is behind her.
    case backlit
    case ready
}

/// Turns what the phone sees into plain advice (Phase 33b). The try-on photo is ideally taken with
/// the app, so these hints aim at what try-on needs: her whole body in view, facing the camera,
/// arms a little away from her body, in good light. No pose is changed by the AI, so the photo has
/// to show the pose she wants to wear clothes in.
///
/// Hair is never mentioned: any hairstyle is fine (Jose, 19 October 2026). Hats, scarves and
/// turtlenecks aren't detected; the screen says once that the picture is best without them.
public enum FramingGuidance {
    public enum Limits {
        /// A joint the body tracking is less sure of than this is treated as not found.
        public static let jointConfidence = 0.3
        /// Her top and bottom must be this far inside the frame.
        public static let edgeMargin = 0.02
        /// Below this share of the frame's height she's too far away to show the clothes.
        public static let minimumHeight = 0.55
        /// How far her middle may be from the frame's middle, as a share of the width.
        public static let centerTolerance = 0.2
        /// Shoulder width over body height: side on it drops under this, facing it is about 0.25.
        public static let minimumShoulderShare = 0.14
        /// A wrist this close to her middle, in shoulder widths, means her arms are against her
        /// body (hanging relaxed it's about 0.6 to 0.8, arms a little away is 0.85 or more).
        public static let armReach = 0.8
        /// A wrist this far above her hip line (as a share of the frame's height) means hands on
        /// her hips or raised.
        public static let wristAboveHip = 0.03
        /// Darker than this and the picture will be muddy.
        public static let darkest = 0.22
        /// The light is behind her when the frame is this much brighter than she is.
        public static let backlitGap = 0.3
        public static let backlitSubject = 0.4
    }

    /// Everything to fix, most urgent first. Empty means the framing is good.
    public static func issues(in observation: FramingObservation) -> [FramingAdvice] {
        guard observation.people > 0, let body = observation.body else {
            return observation.frameBrightness < Limits.darkest ? [.moreLight] : [.noOneInView]
        }
        guard observation.people == 1 else { return [.moreThanOne] }
        var issues: [FramingAdvice] = []

        let cutOff =
            body.minY < Limits.edgeMargin || body.maxY > 1 - Limits.edgeMargin
            || (hasJoints(observation) && !anAnkleIsVisible(observation))
        if cutOff {
            issues.append(.stepBack)
        } else if body.height < Limits.minimumHeight {
            issues.append(.stepCloser)
        }
        if abs(body.midX - 0.5) > Limits.centerTolerance { issues.append(.center) }
        if isNotFacing(observation, body: body) { issues.append(.faceTheCamera) }
        if armsAreClose(observation) { issues.append(.armsOut) }

        let subject = observation.subjectBrightness ?? observation.frameBrightness
        if subject < Limits.darkest {
            issues.append(.moreLight)
        } else if observation.frameBrightness - subject > Limits.backlitGap, subject < Limits.backlitSubject {
            issues.append(.backlit)
        }
        return issues
    }

    /// The one thing to say now: the most urgent issue, or `.ready`. `nil` (no frame yet) is
    /// `.starting`.
    public static func advice(for observation: FramingObservation?) -> FramingAdvice {
        guard let observation else { return .starting }
        return issues(in: observation).first ?? .ready
    }

    private static func hasJoints(_ observation: FramingObservation) -> Bool {
        observation.joint(.neck) != nil || observation.joint(.leftShoulder) != nil
            || observation.joint(.rightShoulder) != nil
    }

    private static func anAnkleIsVisible(_ observation: FramingObservation) -> Bool {
        [FramingObservation.Joint.leftAnkle, .rightAnkle].contains { name in
            guard let ankle = observation.joint(name) else { return false }
            return ankle.y <= 1 - Limits.edgeMargin
        }
    }

    /// Facing away (no face joints, shoulders found) or turned sideways (shoulders close together
    /// for her height).
    private static func isNotFacing(_ observation: FramingObservation, body: CGRect) -> Bool {
        let leftShoulder = observation.joint(.leftShoulder)
        let rightShoulder = observation.joint(.rightShoulder)
        guard let leftShoulder, let rightShoulder else { return false }
        let faceFound = [FramingObservation.Joint.nose, .leftEye, .rightEye].contains { observation.joint($0) != nil }
        if !faceFound { return true }
        let width = abs(leftShoulder.x - rightShoulder.x) * observation.aspect
        return body.height > 0 && width / body.height < Limits.minimumShoulderShare
    }

    /// Hands on hips, up near her face or arms against her sides.
    private static func armsAreClose(_ observation: FramingObservation) -> Bool {
        guard let leftShoulder = observation.joint(.leftShoulder),
            let rightShoulder = observation.joint(.rightShoulder),
            let leftHip = observation.joint(.leftHip), let rightHip = observation.joint(.rightHip)
        else { return false }
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x) * observation.aspect
        guard shoulderWidth > 0 else { return false }
        let middle = (leftHip.x + rightHip.x) / 2
        let hipLine = (leftHip.y + rightHip.y) / 2
        for name in [FramingObservation.Joint.leftWrist, .rightWrist] {
            guard let wrist = observation.joint(name) else { continue }
            let reach = abs(wrist.x - middle) * observation.aspect / shoulderWidth
            if reach < Limits.armReach || wrist.y < hipLine - Limits.wristAboveHip { return true }
        }
        return false
    }
}

/// Keeps the advice steady and times the photo (Phase 33b). Live frames flicker, so the advice
/// changes only after two frames in a row agree. When the framing is good and stays good for
/// `steadyFor` seconds, a countdown starts, and the photo is taken when it ends. Any new advice
/// stops the countdown. Time comes in as arguments, so it's all testable.
public struct FramingCoach: Sendable, Equatable {
    /// What to show now.
    public private(set) var advice: FramingAdvice = .starting
    /// 3, 2 or 1 while the photo is about to be taken, otherwise `nil`.
    public private(set) var countdown: Int?
    /// True once the photo has been asked for. Nothing more is asked until `reset`.
    public private(set) var hasFired = false

    public let steadyFor: TimeInterval
    public let countdownFrom: Int

    private var candidate: FramingAdvice = .starting
    private var agreeing = 0
    private var readySince: Date?

    public init(steadyFor: TimeInterval = 1, countdownFrom: Int = 3) {
        self.steadyFor = steadyFor
        self.countdownFrom = countdownFrom
    }

    /// The advice for the latest frame.
    public mutating func observe(_ raw: FramingAdvice, at time: Date) {
        guard !hasFired else { return }
        if raw == candidate {
            agreeing += 1
        } else {
            candidate = raw
            agreeing = 1
        }
        guard agreeing >= 2, candidate != advice else { return }
        advice = candidate
        if advice == .ready {
            readySince = time
        } else {
            readySince = nil
            countdown = nil
        }
    }

    /// Moves the countdown on. True the moment the photo should be taken (once).
    public mutating func tick(at time: Date) -> Bool {
        guard !hasFired, advice == .ready, let readySince else { return false }
        let elapsed = time.timeIntervalSince(readySince) - steadyFor
        guard elapsed >= 0 else { return false }
        let remaining = countdownFrom - Int(elapsed.rounded(.down))
        if remaining <= 0 {
            countdown = nil
            hasFired = true
            return true
        }
        countdown = remaining
        return false
    }

    /// Starts again, after a photo or when the camera comes back.
    public mutating func reset() {
        self = FramingCoach(steadyFor: steadyFor, countdownFrom: countdownFrom)
    }

    /// Stops the photo being taken on its own, as when she taps the shutter herself.
    public mutating func markTaken() {
        hasFired = true
        countdown = nil
    }
}

/// Looks at a camera frame or a photo, on the phone (Apple Vision in `Services`). The frame is
/// looked at and dropped: nothing is stored or sent.
public protocol FrameAnalyzing: Sendable {
    /// `nil` when the frame couldn't be looked at (Vision isn't available, as on a simulator).
    func observe(_ frame: AnalysisFrame) async -> FramingObservation?
}

/// One picture to look at: a camera frame, or the photo she picked or took.
public struct AnalysisFrame: @unchecked Sendable {
    public enum Source {
        case buffer(CVPixelBuffer)
        case image(CGImage)
    }

    public let source: Source

    public init(_ buffer: CVPixelBuffer) { source = .buffer(buffer) }
    public init(_ image: CGImage) { source = .image(image) }
}
