import Models

/// A photo she took or picked for her try-on photo, kept without its metadata and already checked
/// on the phone, but not yet her try-on photo (Phase 33b). She sees what the check found, then uses
/// it or lets it go. Until she uses it, her current try-on photo is untouched.
struct TryOnPhotoCandidate: Equatable, Sendable {
    var photo: PhotoReference
    /// Where it came from, so "take another" or "choose another" goes back to the same place.
    var source: PhotoSource
    var check: TryOnPhotoCheck
}
