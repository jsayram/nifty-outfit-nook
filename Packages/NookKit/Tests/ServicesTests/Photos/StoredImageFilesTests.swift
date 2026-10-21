import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// Files nothing points to (Phase 22b): the launch sweep, letting go of a deleted record's
/// files, a piece deleted for good taking its photo, cutout and pictures' files with it, and
/// backups carrying exactly the files her records point to.
struct StoredImageFilesTests {
    /// A small real JPEG, so thumbnails can be made of it.
    static let jpeg = SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 300, height: 400)

    /// A photo file written straight into the phone's photo folder, as an earlier launch would
    /// have left it (so the launch sweep doesn't treat it as new).
    static func plant(_ id: String, on phone: BackupTestBed) throws {
        try BackupLocation.prepare(phone.location.photos, backedUp: true)
        try jpeg.write(to: try #require(phone.photos.url(for: id)))
    }

    static func files(_ phone: BackupTestBed) throws -> StoredImageFiles {
        try #require(phone.storage.imageFiles)
    }

    static func stored(_ id: String) -> PhotoReference { .stored(EntityID(id)) }

    static func thumbnailNames(_ phone: BackupTestBed) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: phone.location.thumbnails.path)) ?? [])
    }

    /// Services on the phone's own stores, with its image files, as the app builds them.
    static func services(_ phone: BackupTestBed) throws -> NookServices {
        var services = FixtureServices.make(
            set: .empty, stores: phone.storage.stores, now: TestTime.now, calendar: TestTime.calendar)
        services.imageFiles = try files(phone)
        return services
    }

    static func piece(_ id: Garment.ID, photo: String, cutout: String? = nil, deletedAt: Date? = nil) -> Garment {
        Garment(
            id: id, name: "Piece \(id)", category: .top, photo: stored(photo),
            cutout: cutout.map { GarmentCutout(image: stored($0), quality: StandInCutoutService.cleanQuality) },
            deletedAt: deletedAt, addedAt: TestTime.day(-60))
    }

    static func look(_ id: Look.ID, pieces: [Garment.ID]) -> Look {
        Look(
            id: id, pieces: pieces.map { LookPiece(id: LookPiece.ID("\(id)-\($0)"), content: .garment($0)) },
            name: "Look \(id)", isSaved: true, createdAt: TestTime.day(-2))
    }

    // MARK: The launch sweep

    /// Everything a record points to stays: pieces and cutouts, Recently deleted, a draft and
    /// what it started from, the try-on photo, a stored picture and a copy kept for review.
    /// Files nothing points to go, with their thumbnails, and so does anything that isn't a photo.
    @Test func theSweepKeepsWhatRecordsPointToAndNothingElse() async throws {
        let phone = try BackupTestBed("sweep")
        let kept = [
            "photo-a", "cutout-a", "photo-deleted", "draft-new", "draft-base", "tryon-photo", "picture-1",
            "conflict-photo",
        ]
        for id in kept + ["orphan-1", "orphan-2"] { try Self.plant(id, on: phone) }
        try Data("half written".utf8).write(to: phone.location.photos.appending(path: ".dat.nosync1a2b"))

        try await phone.storage.closet.save(Self.piece("g-a", photo: "photo-a", cutout: "cutout-a"))
        try await phone.storage.closet.save(Self.piece("g-gone", photo: "photo-deleted", deletedAt: TestTime.day(-3)))
        var details = GarmentDetails(name: "New")
        details.photo = Self.stored("draft-new")
        var base = GarmentDetails(name: "Old")
        base.photo = Self.stored("draft-base")
        try await phone.storage.drafts.save(
            GarmentDraft(target: .newPiece, step: .details, details: details, base: base, savedAt: TestTime.now))
        var profile = Profile()
        profile.tryOnPhoto = Self.stored("tryon-photo")
        try await phone.storage.profile.save(profile)
        let look = Self.look("l-1", pieces: ["g-a"])
        try await phone.storage.looks.save(look)
        try await phone.storage.pictures.save(
            TryOnPicture(id: "t-1", of: look, image: .generated(Self.stored("picture-1")), createdAt: TestTime.now))
        let reviewed = Self.piece("g-review", photo: "conflict-photo")
        try RecordTable<StoredConflict>(kind: .restoreConflict).write(
            [
                "garment/g-review": StoredConflict(
                    kind: "garment", key: "g-review", payloadVersion: RecordPayload.currentVersion,
                    payload: try RecordPayload.encode(reviewed), foundAt: TestTime.now)
            ], in: ModelContext(phone.storage.container))

        let files = try Self.files(phone)
        for id in ["photo-a", "orphan-1"] {
            _ = files.thumbnails.data(for: id, maxPixelSize: 512) { Self.jpeg }
        }

        await files.removeUnused()

        #expect(Set(phone.photos.ids()) == Set(kept))
        #expect(
            (try FileManager.default.contentsOfDirectory(atPath: phone.location.photos.path)).count == kept.count)
        #expect(Self.thumbnailNames(phone) == ["photo-a-512"])
    }

    /// A photo written since launch may be waiting for its draft to be saved, so the sweep leaves
    /// it; the next launch's sweep takes it if nothing ever pointed to it.
    @Test func aPhotoWrittenSinceLaunchIsLeftAlone() async throws {
        let phone = try BackupTestBed("new-photo")
        let new = try PhotoFileStore(directory: phone.location.photos).add(Self.jpeg)
        try await Self.files(phone).removeUnused()
        #expect(phone.photos.ids() == [new])
    }

    @Test func anEmptyPhoneHasNothingToSweep() async throws {
        let phone = try BackupTestBed("empty-sweep")
        try await Self.files(phone).removeUnused()
        #expect(phone.photos.ids().isEmpty)
    }

    // MARK: Letting go

    @Test func aFileStillPointedToIsNeverReleased() async throws {
        let phone = try BackupTestBed("shared")
        for id in ["shared", "alone"] { try Self.plant(id, on: phone) }
        try await phone.storage.closet.save(Self.piece("g-1", photo: "shared"))
        let files = try Self.files(phone)
        _ = files.thumbnails.data(for: "alone", maxPixelSize: 512) { Self.jpeg }

        await files.release(
            [Self.stored("shared"), Self.stored("alone"), .sample("navy"), .noPhoto], deletedForGood: false)

        #expect(phone.photos.ids() == ["shared"])
        #expect(Self.thumbnailNames(phone).isEmpty)
    }

    /// A piece deleted for good leaves the restore's safety copy too, so Undo restore can't bring
    /// its photo back; a deleted picture doesn't.
    @Test func deletedForGoodAlsoLeavesTheSafetyCopy() async throws {
        let phone = try BackupTestBed("safety")
        try BackupLocation.prepare(phone.location.safetyPhotos)
        for id in ["purged", "picture"] {
            try Self.plant(id, on: phone)
            try Self.jpeg.write(to: phone.location.safetyPhotos.appending(path: id))
        }
        let files = try Self.files(phone)

        await files.release([Self.stored("picture")], deletedForGood: false)
        await files.release([Self.stored("purged")], deletedForGood: true)

        #expect(phone.photos.ids().isEmpty)
        #expect(PhotoFiles(directory: phone.location.safetyPhotos).ids() == ["picture"])
    }

    // MARK: Deleting a piece for good

    /// Delete now: the piece's photo and cutout, the try-on pictures that show it with their
    /// files, its unsaved Edit's new photo and every thumbnail go. Another piece keeps its photo.
    @Test func deleteNowTakesEveryFileOfThePiece() async throws {
        let phone = try BackupTestBed("delete-now")
        for id in ["photo-1", "cutout-1", "edit-photo", "picture-1", "photo-2", "picture-2"] {
            try Self.plant(id, on: phone)
        }
        try await phone.storage.closet.save(Self.piece("g-1", photo: "photo-1", cutout: "cutout-1"))
        try await phone.storage.closet.save(Self.piece("g-2", photo: "photo-2"))
        var edit = GarmentDetails(name: "Edited")
        edit.photo = Self.stored("edit-photo")
        var base = GarmentDetails(name: "Piece g-1")
        base.photo = Self.stored("photo-1")
        try await phone.storage.drafts.save(
            GarmentDraft(target: .garment("g-1"), step: .details, details: edit, base: base, savedAt: TestTime.now))
        let both = Self.look("l-both", pieces: ["g-1", "g-2"])
        let other = Self.look("l-other", pieces: ["g-2"])
        try await phone.storage.looks.save(both)
        try await phone.storage.looks.save(other)
        try await phone.storage.pictures.save(
            TryOnPicture(id: "t-1", of: both, image: .generated(Self.stored("picture-1")), createdAt: TestTime.now))
        try await phone.storage.pictures.save(
            TryOnPicture(id: "t-2", of: other, image: .generated(Self.stored("picture-2")), createdAt: TestTime.now))
        let services = try Self.services(phone)
        for id in ["photo-1", "cutout-1", "picture-1", "photo-2"] {
            _ = try Self.files(phone).thumbnails.data(for: id, maxPixelSize: 512) { Self.jpeg }
        }

        try await phone.storage.closet.delete("g-1", at: TestTime.day(-1))
        try await PermanentDeletion.delete("g-1", in: services)

        #expect(Set(phone.photos.ids()) == ["photo-2", "picture-2"])
        #expect(Self.thumbnailNames(phone) == ["photo-2-512"])
        #expect(try await phone.storage.pictures.pictures().map(\.id) == ["t-2"])
    }

    /// The 30-day purge does the same for every piece whose time is up, and only those.
    @Test func theMonthlyPurgeTakesTheFilesOfExpiredPiecesOnly() async throws {
        let phone = try BackupTestBed("purge")
        for id in ["old-photo", "old-cutout", "old-picture", "recent-photo"] { try Self.plant(id, on: phone) }
        try await phone.storage.closet.save(Self.piece("g-old", photo: "old-photo", cutout: "old-cutout"))
        try await phone.storage.closet.save(Self.piece("g-recent", photo: "recent-photo"))
        let look = Self.look("l-old", pieces: ["g-old"])
        try await phone.storage.looks.save(look)
        try await phone.storage.pictures.save(
            TryOnPicture(id: "t-old", of: look, image: .generated(Self.stored("old-picture")), createdAt: TestTime.now))
        try await phone.storage.closet.delete("g-old", at: TestTime.day(-31))
        try await phone.storage.closet.delete("g-recent", at: TestTime.day(-2))

        let purged = try await PermanentDeletion.purgeExpired(asOf: TestTime.now, in: try Self.services(phone))

        #expect(purged == ["g-old"])
        #expect(phone.photos.ids() == ["recent-photo"])
    }

    // MARK: Backups carry exactly the right files

    /// After Delete now, an export carries the files her records point to and nothing else: the
    /// remaining photo, cutout and stored picture, and no thumbnails. Restored on a new phone, each
    /// is back byte for byte.
    @Test func anExportAfterDeleteNowCarriesExactlyTheRightFiles() async throws {
        let phone = try BackupTestBed("export-after-delete")
        for id in ["photo-1", "photo-2", "cutout-2", "picture-2", "orphan"] { try Self.plant(id, on: phone) }
        try await phone.storage.closet.save(Self.piece("g-1", photo: "photo-1"))
        try await phone.storage.closet.save(Self.piece("g-2", photo: "photo-2", cutout: "cutout-2"))
        let look = Self.look("l-2", pieces: ["g-2"])
        try await phone.storage.looks.save(look)
        try await phone.storage.pictures.save(
            TryOnPicture(id: "t-2", of: look, image: .generated(Self.stored("picture-2")), createdAt: TestTime.now))
        _ = try Self.files(phone).thumbnails.data(for: "photo-2", maxPixelSize: 512) { Self.jpeg }
        try await phone.storage.closet.delete("g-1", at: TestTime.day(-1))
        try await PermanentDeletion.delete("g-1", in: try Self.services(phone))

        let file = try await phone.export()
        let newPhone = try BackupTestBed("export-after-delete-new")
        let service = newPhone.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        #expect(preview.photos == 3)
        _ = try await service.restore(preview, as: .replace)

        #expect(Set(newPhone.photos.ids()) == ["photo-2", "cutout-2", "picture-2"])
        let before = try photoHashes(phone.photos)
        #expect(try photoHashes(newPhone.photos) == before.filter { $0.key != "orphan" })
        #expect(Self.thumbnailNames(newPhone).isEmpty)
    }

    /// Undo restore after a piece was deleted for good: the piece, its pictures and their files
    /// stay deleted, though the safety copy was taken before.
    @Test func undoRestoreDoesntBringBackAPieceDeletedSince() async throws {
        let phone = try BackupTestBed("undo-after-purge")
        for id in ["photo-1", "picture-1", "photo-2"] { try Self.plant(id, on: phone) }
        try await phone.storage.closet.save(Self.piece("g-1", photo: "photo-1"))
        try await phone.storage.closet.save(Self.piece("g-2", photo: "photo-2"))
        let look = Self.look("l-1", pieces: ["g-1"])
        try await phone.storage.looks.save(look)
        try await phone.storage.pictures.save(
            TryOnPicture(id: "t-1", of: look, image: .generated(Self.stored("picture-1")), createdAt: TestTime.now))
        let file = try await phone.export()
        let service = phone.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        _ = try await service.restore(preview, as: .replace)
        phone.storage.reload()

        try await phone.storage.closet.delete("g-1", at: TestTime.day(-1))
        try await PermanentDeletion.delete("g-1", in: try Self.services(phone))
        #expect(!PhotoFiles(directory: phone.location.safetyPhotos).ids().contains("photo-1"))
        try await phone.service().undoRestore()
        try await Self.files(phone).removeUnused()

        let rows = try phone.rows()
        #expect(!rows.contains { $0.kind == "garment" && $0.key == "g-1" })
        #expect(!rows.contains { $0.kind == "picture" && $0.key == "t-1" })
        #expect(rows.contains { $0.kind == "garment" && $0.key == "g-2" })
        #expect(phone.photos.ids() == ["photo-2"])
    }
}
