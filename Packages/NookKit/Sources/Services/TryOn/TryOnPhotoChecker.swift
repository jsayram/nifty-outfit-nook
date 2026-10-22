import Foundation
import Models

/// Phase 33b: checks a photo for use as her try-on photo, before she saves it. It runs the same
/// `PhoneTryOn.facelessPortrait` that try-on runs before sending anything (her outline, one face,
/// the head and hair filled with grey, no face found in the result, in the pixels and in the JPEG),
/// so a photo it accepts is one try-on accepts. Then, if it can look at the photo's framing, it
/// adds gentle tips from the same rules as the live guidance (`FramingGuidance`).
///
/// Everything runs on the phone. Nothing is sent, and nothing is written: the faceless picture it
/// makes is thrown away.
public struct TryOnPhotoChecker: TryOnPhotoChecking {
    let analyzer: any PersonAnalyzing
    let frames: (any FrameAnalyzing)?
    let files: PhotoFileStore
    let images: any ImageProvider

    public init(
        analyzer: any PersonAnalyzing, frames: (any FrameAnalyzing)? = nil, files: PhotoFileStore,
        images: any ImageProvider
    ) {
        self.analyzer = analyzer
        self.frames = frames
        self.files = files
        self.images = images
    }

    public func check(_ photo: PhotoReference) async -> TryOnPhotoCheck {
        guard photo != .noPhoto else { return .problem(.noTryOnPhoto) }
        guard let original = await data(for: photo),
            let bitmap = TryOnBitmap.decode(original, maxPixelSize: PhoneTryOn.workingSize)
        else { return .problem(.photoUnreadable) }
        do {
            _ = try await PhoneTryOn.facelessPortrait(of: bitmap, using: analyzer)
        } catch {
            return .problem(error)
        }
        return .fine(tips: await tips(for: bitmap))
    }

    /// What would make the picture better. Only what the photo itself shows: not where she stands in
    /// the frame, since she isn't taking it now.
    private func tips(for bitmap: TryOnBitmap) async -> [FramingAdvice] {
        guard let frames, let image = bitmap.cgImage, let seen = await frames.observe(AnalysisFrame(image)) else {
            return []
        }
        let tips: Set<FramingAdvice> = [.stepBack, .stepCloser, .faceTheCamera, .armsOut, .moreLight, .backlit]
        return FramingGuidance.issues(in: seen).filter(tips.contains)
    }

    private func data(for reference: PhotoReference) async -> Data? {
        if case .stored(let id) = reference { return files.data(for: id.rawValue) }
        return try? await images.imageData(for: reference, maxPixelSize: 2 * PhoneTryOn.workingSize)
    }
}
