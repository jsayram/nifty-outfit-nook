import Fixtures
import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Features

/// A photo intake like the real one (Phase 22a): the screen picks, and `keep` hands back a new
/// stored photo each time. It records what it kept and discarded.
final class RecordingPhotoIntake: PhotoIntake {
    enum Outcome: Sendable {
        case keeps
        case fails(PhotoIntakeError)
    }

    private let state = Mutex<(kept: [Data], discarded: [PhotoReference], next: Int)>(([], [], 0))
    let outcome: Outcome

    init(_ outcome: Outcome = .keeps) {
        self.outcome = outcome
    }

    var sources: [PhotoSource] { [.camera, .library] }
    var usesSystemPicker: Bool { true }
    var kept: [Data] { state.withLock { $0.kept } }
    var discarded: [PhotoReference] { state.withLock { $0.discarded } }

    func photo(from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference { throw .unreadable }

    func keep(_ data: Data, from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference {
        if case .fails(let error) = outcome { throw error }
        return state.withLock {
            $0.kept.append(data)
            $0.next += 1
            return .stored(EntityID("photo-\($0.next)"))
        }
    }

    func discard(_ photo: PhotoReference) async {
        state.withLock { $0.discarded.append(photo) }
    }
}

extension PickedPhoto {
    static func bytes(_ text: String = "photo", from source: PhotoSource = .library) -> PickedPhoto {
        PickedPhoto(source: source) { Data(text.utf8) }
    }

    static let unreadable = PickedPhoto(source: .library) { throw PhotoIntakeError.unreadable }
}

/// Add a piece with real photos (Phase 22a).
@MainActor
struct RealPhotoIntakeTests {
    private func services(_ intake: RecordingPhotoIntake) -> NookServices {
        var services = editorServices()
        services.photos = intake
        return services
    }

    @Test func realPhotosOfferTheCameraAndPhotosOnly() async {
        let model = await loadedEditor(services: services(RecordingPhotoIntake()))
        #expect(model.usesSystemPicker)
        #expect(model.photoSources == [.camera, .library])
    }

    @Test func theStandInKeepsItsThreeChoices() async {
        let model = await loadedEditor(services: editorServices())
        #expect(!model.usesSystemPicker)
        #expect(model.photoSources == PhotoSource.allCases)
    }

    @Test func aPickedPhotoIsKeptAndMovesOnToTheForm() async {
        let intake = RecordingPhotoIntake()
        let model = await loadedEditor(services: services(intake))
        await model.keepPhoto(.bytes("tee"), using: intake)
        #expect(model.details.photo == .stored(EntityID("photo-1")))
        #expect(model.step == .details)
        #expect(model.photoState == .idle)
        #expect(intake.kept == [Data("tee".utf8)])
    }

    @Test func aPhotoReplacedBeforeSavingIsDeleted() async {
        let intake = RecordingPhotoIntake()
        let model = await loadedEditor(services: services(intake))
        await model.keepPhoto(.bytes("first"), using: intake)
        await model.keepPhoto(.bytes("second", from: .camera), using: intake)
        #expect(model.details.photo == .stored(EntityID("photo-2")))
        #expect(intake.discarded == [.stored(EntityID("photo-1"))])
    }

    @Test func discardingThePieceDeletesItsUnsavedPhoto() async {
        let intake = RecordingPhotoIntake()
        let model = await loadedEditor(services: services(intake))
        await model.keepPhoto(.bytes(), using: intake)
        await model.discardChanges()
        #expect(intake.discarded == [.stored(EntityID("photo-1"))])
    }

    @Test func aSavedPieceKeepsItsPhoto() async throws {
        let intake = RecordingPhotoIntake()
        let services = services(intake)
        let model = await loadedEditor(services: services)
        await model.keepPhoto(.bytes(), using: intake)
        model.details.name = "Sage cardigan"
        model.details.category = .layer
        let saved = try #require(await model.save(in: services.closet))
        #expect(saved.garment.photo == .stored(EntityID("photo-1")))
        #expect(intake.discarded.isEmpty)
    }

    @Test func editingNeverDeletesThePiecesSavedPhoto() async throws {
        let intake = RecordingPhotoIntake()
        let services = services(intake)
        let garment = try #require(try await services.closet.garments().first { $0.isInCloset })
        let model = await loadedEditor(.garment(garment.id), services: services)
        await model.keepPhoto(.bytes(), using: intake)
        await model.discardChanges()
        // Only the new, unsaved photo goes; the piece's own photo stays.
        #expect(intake.discarded == [.stored(EntityID("photo-1"))])
    }

    @Test func discardingAWaitingDraftDeletesItsPhoto() async throws {
        let intake = RecordingPhotoIntake()
        let services = services(intake)
        let first = await loadedEditor(services: services)
        await first.keepPhoto(.bytes(), using: intake)
        await first.saveDraftNow()

        let second = await loadedEditor(services: services)
        #expect(second.phase == .offeringResume)
        await second.discardPendingDraft()
        #expect(intake.discarded == [.stored(EntityID("photo-1"))])
    }

    @Test func aPhotoThatCantBeLoadedChangesNothing() async {
        let intake = RecordingPhotoIntake()
        let model = await loadedEditor(services: services(intake))
        await model.keepPhoto(.unreadable, using: intake)
        #expect(model.photoState == .failed)
        #expect(model.step == .choose)
        #expect(model.details.photo == .noPhoto)
        #expect(intake.kept.isEmpty)
    }

    @Test func aPhotoThatCantBeSavedSaysSo() async {
        let intake = RecordingPhotoIntake(.fails(.notSaved))
        let model = await loadedEditor(services: services(intake))
        await model.keepPhoto(.bytes(), using: intake)
        #expect(model.photoState == .notSaved)
        #expect(model.details.photo == .noPhoto)
        model.clearPhotoProblem()
        #expect(model.photoState == .idle)
    }

    @Test func aCancelledKeepIsQuiet() async {
        let intake = RecordingPhotoIntake(.fails(.cancelled))
        let model = await loadedEditor(services: services(intake))
        await model.keepPhoto(.bytes(), using: intake)
        #expect(model.photoState == .idle)
        #expect(model.step == .choose)
    }
}
