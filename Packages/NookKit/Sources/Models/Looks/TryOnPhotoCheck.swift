import Foundation

/// What the phone found when it checked a try-on photo, before she saved it as her try-on photo
/// (Phase 33b). It runs the same fail-closed checks try-on runs before sending anything (33a), so
/// a photo she's told is fine is one try-on will accept, and a photo that wouldn't work is explained
/// then, not when she tries a look on.
public enum TryOnPhotoCheck: Sendable, Equatable {
    /// Try-on can use this photo. `tips` are gentle things that would make the picture better, from
    /// the same framing rules as the live guidance (never about her hair).
    case fine(tips: [FramingAdvice])
    /// Try-on couldn't use it, and why. Nothing was sent: the check runs on the phone.
    case problem(TryOnPrepareProblem)
}

/// Checks a stored photo for use as the try-on photo, on the phone. `Services` has the one built
/// on Apple Vision and 33a's head masking.
public protocol TryOnPhotoChecking: Sendable {
    func check(_ photo: PhotoReference) async -> TryOnPhotoCheck
}
