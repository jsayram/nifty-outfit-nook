import Features
import Foundation
import Models
import Networking
import Services

#if DEBUG
    import Fixtures
#endif

/// Real try-on pictures (Phase 33a), with her face kept on the phone. With the real backend
/// configured (`docs/backend-switch.md`), or `-cloud-tryon [normal|slow|fails]` against the
/// in-process fake backend in debug builds. Otherwise Stage A's simulated pictures, which send
/// nothing. The backend only calls the image provider when its key is set (backend README,
/// "Try-on (33a)"); until then it answers with a stand-in picture.
///
/// On an iPhone the person, face and pose checks are Apple Vision's (`VisionPersonAnalyzer`).
/// Simulators can't run them, so there every check fails and nothing is ever sent, except in a
/// debug build with `-cloud-tryon`, which reads the drawn stand-in photo that `-seed-tryon` sets
/// up (`SyntheticPersonAnalyzer`). No sample photo of a person is used for this.
nonisolated enum AppTryOn {
    static func install(
        into services: inout NookServices, paid: (any PaidActionService)?, files: PhotoFileStore,
        analyzer: any PersonAnalyzing, keepsSettings: Bool = true
    ) {
        guard let paid else { return }
        services.tryOnConsent = keepsSettings ? DefaultsTryOnConsentStore() : InMemoryTryOnConsentStore()
        services.tryOnPipeline = PhoneTryOn(analyzer: analyzer, paid: paid, files: files, images: services.images)
        // Pictures now need styling access or a credit (30a, 30b), checked again on the server.
        services.tryOnIsSimulated = false
    }

    @MainActor
    static func usesCloud(_ arguments: [String]) -> Bool {
        if AppGateway.settings.usesRealServices { return true }
        #if DEBUG
            return arguments.contains("-cloud-tryon")
        #else
            return false
        #endif
    }

    /// Apple Vision, except for a debug build on the simulator running against the fake backend, or
    /// with `-fake-camera` (33b).
    @MainActor
    static func analyzer(arguments: [String]) -> any PersonAnalyzing {
        #if DEBUG && targetEnvironment(simulator)
            if !AppGateway.settings.usesRealServices,
                arguments.contains("-cloud-tryon") || arguments.contains("-fake-camera")
            {
                return SyntheticPersonAnalyzer()
            }
        #endif
        return VisionPersonAnalyzer()
    }

    /// Phase 33b: the try-on photo's setup, with her own photos. The photo is checked on the phone
    /// with the same checks try-on runs (`TryOnPhotoChecker`), and the camera's live hints come
    /// from Vision on the camera's frames (`VisionFrameAnalyzer`). Both run on the phone and send
    /// nothing, so they don't wait for the backend.
    static func installPhotoSetup(
        into services: inout NookServices, files: PhotoFileStore, analyzer: any PersonAnalyzing
    ) {
        let frames = VisionFrameAnalyzer()
        services.frameAnalyzer = frames
        services.tryOnPhotoChecker = TryOnPhotoChecker(
            analyzer: analyzer, frames: frames, files: files, images: services.images)
    }

    #if DEBUG
        /// `-fake-camera [away|two]` (33b): the try-on photo's camera is a stand-in, since the
        /// simulator has none. It shows a drawn person (`SyntheticPerson`, never a photo of anyone),
        /// gives hints in turn, and "takes" that drawing. `away` draws her facing away and `two`
        /// draws two people, so the check before saving can be seen refusing.
        @MainActor
        static func cameraMaker(arguments: [String]) -> TryOnCameraMaker? {
            guard DebugTryOnCamera.isOn else { return nil }
            let kind = DebugLaunchArgument.value(after: "-fake-camera", in: arguments)
            let drawing: TryOnBitmap
            switch kind {
            case "away": drawing = SyntheticPerson.draw(width: 600, height: 800, facingAway: true).bitmap
            case "two": drawing = SyntheticPerson.draw(width: 600, height: 800, centers: [0.3, 0.7]).bitmap
            default: drawing = SyntheticPerson.draw(width: 600, height: 800).bitmap
            }
            guard let photo = drawing.png() else { return nil }
            return DebugTryOnCamera.maker(photo: photo)
        }

        /// `-cloud-tryon [normal|slow|fails]` against the fake backend: signs in with the fake Apple
        /// sign-in at launch (paid requests need an account) and sets how its image service behaves.
        @MainActor
        static func prepareFakeIfAsked(arguments: [String]) async {
            guard let fake = AppGateway.fake,
                let value = DebugLaunchArgument.value(after: "-cloud-tryon", in: arguments)
                    ?? (arguments.contains("-cloud-tryon") ? "normal" : nil)
            else { return }
            fake.backend.setTryOn(FakeTryOnBehaviour(rawValue: value) ?? .normal)
            if !(await fake.account.isSignedIn()) { _ = try? await fake.account.signIn() }
        }

        /// `-seed-tryon`: her own closet in the store gets three pieces with drawn photos, one saved
        /// look of them, and a drawn stand-in try-on photo (`SyntheticPerson`, never a person),
        /// then onboarding is finished. Only once: a closet that already has the look is left as it
        /// is. For the 33a checkpoint on the simulator.
        static func seedIfAsked(arguments: [String], storage: NookStorage, photos: PhotoFileStore) async {
            guard arguments.contains("-seed-tryon"), (try? await storage.looks.look("l-tryon-checkpoint")) == nil
            else { return }
            let now = Date.now
            let pieces: [(String, GarmentCategory, GarmentSubKind, ColorName, SyntheticGarmentPhotos.Scene)] = [
                ("Striped sweater", .top, .sweater, .navy, .stripedSweater),
                ("Grey trousers", .bottom, .trousers, .gray, .cutOffTrousers),
                ("Satin skirt", .bottom, .skirt, .pink, .shinySkirt),
            ]
            var garments: [Garment] = []
            for (index, piece) in pieces.enumerated() {
                guard let photo = try? photos.add(SyntheticGarmentPhotos.jpeg(piece.4, width: 900, height: 1125)) else {
                    return
                }
                var garment = Garment(
                    id: .init("g-tryon-\(index)"), name: piece.0, category: piece.1, subKind: piece.2,
                    colors: [piece.3], addedAt: now.addingTimeInterval(Double(-index) * 60))
                garment.photo = .stored(EntityID(photo))
                try? await storage.closet.save(garment)
                garments.append(garment)
            }
            let look = Look(
                id: .init("l-tryon-checkpoint"),
                pieces: [garments[0], garments[1]].map { LookPiece(id: .random(), content: .garment($0.id)) },
                name: "Sweater and trousers", occasion: .casual, isSaved: true, savedAt: now, createdAt: now)
            try? await storage.looks.save(look)
            if let person = SyntheticPerson.draw(width: 600, height: 800).bitmap.png(),
                let id = try? photos.add(person)
            {
                _ = try? await storage.profile.update { $0.tryOnPhoto = .stored(EntityID(id)) }
            }
            try? await storage.onboarding.complete(startingCloset: .empty)
        }
    #endif
}
