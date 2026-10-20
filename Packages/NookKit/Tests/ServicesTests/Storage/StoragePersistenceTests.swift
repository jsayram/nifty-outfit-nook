import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// Phase 21a's checkpoint, in code: what she makes survives a relaunch, every field of it, and
/// Delete my data leaves nothing behind. "A relaunch" is a new `NookStorage` on the same folder.
struct StoragePersistenceTests {
    private static let demo = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)

    /// Every demo record, and 300 of the large closet's garments, come back from a relaunch
    /// exactly as saved: garments, looks, suitcases, pictures and the profile.
    @Test func everyFixtureRecordSurvivesARelaunch() async throws {
        let store = try TemporaryStore("fixtures")
        let large = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)
        let garments = Self.demo.garments + large.garments.prefix(300)
        do {
            let storage = try store.open()
            for garment in garments { try await storage.closet.save(garment) }
            for look in Self.demo.looks { try await storage.looks.save(look) }
            for suitcase in Self.demo.suitcases { try await storage.suitcases.restore(suitcase) }
            for picture in Self.demo.pictures { try await storage.pictures.save(picture) }
            try await storage.profile.save(Self.demo.profile)
        }

        let relaunched = try store.open()
        let read = Dictionary(uniqueKeysWithValues: try await relaunched.closet.garments().map { ($0.id, $0) })
        #expect(read.count == garments.count)
        for garment in garments {
            #expect(read[garment.id] == (try StoreValidation.garment(garment)))
        }
        let looks = try Self.demo.looks.map { try StoreValidation.look($0) }
        #expect(Set(try await relaunched.looks.looks()) == Set(looks))
        #expect(Set(try await relaunched.suitcases.suitcases()) == Set(Self.demo.suitcases))
        #expect(Set(try await relaunched.pictures.pictures()) == Set(Self.demo.pictures))
        #expect(try await relaunched.profile.profile() == (try StoreValidation.profile(Self.demo.profile)))
    }

    /// Changes made through each store call are on disk when the call returns: wear, laundry,
    /// Recently deleted, a renamed suitcase, the remembered source and occasion.
    @Test func changesAreOnDiskWhenTheCallReturns() async throws {
        let store = try TemporaryStore("changes")
        let tee = try #require(Self.demo.garments.first { $0.id == "g-black-tee" })
        let weekend = try #require(Self.demo.suitcases.first)
        do {
            let storage = try store.open()
            try await storage.closet.save(tee)
            try await storage.suitcases.restore(weekend)
            try await storage.closet.recordWear(of: [tee.id], on: TestTime.now)
            try await storage.closet.setLaundry(.dirty, for: [tee.id])
            try await storage.closet.delete(tee.id, at: TestTime.day(-2))
            try await storage.suitcases.update(weekend.id) { $0.name = "Away days" }
            try await storage.profile.update {
                $0.remembered = RememberedChoices(source: .suitcase(weekend.id), occasion: .dateNight)
            }
        }

        let relaunched = try store.open()
        let garment = try await relaunched.closet.garment(tee.id)
        #expect(garment.wornOn.contains { TestTime.calendar.isDate($0, inSameDayAs: TestTime.now) })
        #expect(garment.laundry == .dirty)
        #expect(garment.deletedAt == TestTime.day(-2))
        #expect(try await relaunched.suitcases.suitcase(weekend.id).name == "Away days")
        #expect(
            try await relaunched.profile.profile().remembered
                == RememberedChoices(source: .suitcase(weekend.id), occasion: .dateNight))
    }

    /// Drafts, the unsent feedback note, onboarding and the tours seen are kept; how each tour
    /// ended stays in memory for the session (Personal in the data map).
    @Test func draftsAndAppStateSurviveARelaunch() async throws {
        let store = try TemporaryStore("drafts")
        let add = GarmentDraft(
            target: .newPiece, step: .details, details: GarmentDetails(name: "Sage cardigan"), base: GarmentDetails(),
            description: "Sage green cardigan", savedAt: TestTime.now)
        let edit = GarmentDraft(
            target: .garment("g-navy-trousers"), step: .details, details: GarmentDetails(name: "Navy work trousers"),
            base: GarmentDetails(name: "Navy dress pants"), savedAt: TestTime.day(-1))
        let look = LookDraft(name: "Pink for Friday", garmentIDs: ["g-pink-shirt"], savedAt: TestTime.now)
        let note = FeedbackDraft(kind: .idea, message: "The hamper is lovely", includesDetails: true)
        do {
            let storage = try store.open()
            try await storage.drafts.save(add)
            try await storage.drafts.save(edit)
            try await storage.lookDrafts.save(look)
            try await storage.feedbackDrafts.save(note)
            try await storage.onboarding.complete(startingCloset: .empty)
            try await storage.tours.record(TourRecord(tour: .home, version: 2, outcome: .finished, date: TestTime.now))
            try await storage.tours.setShowsTipsOnNewScreens(false)
        }

        let relaunched = try store.open()
        #expect(try await relaunched.drafts.drafts() == [add, edit])
        #expect(try await relaunched.lookDrafts.draft() == look)
        #expect(try await relaunched.feedbackDrafts.draft() == note)
        #expect(try await relaunched.onboarding.state() == OnboardingState(isCompleted: true, startingCloset: .empty))
        let progress = try await relaunched.tours.progress()
        #expect(progress.seenVersions == [.home: 2])
        #expect(progress.records.isEmpty)
        #expect(!progress.showsTipsOnNewScreens)
    }

    /// "Delete permanently now" lasts: the piece is gone after a relaunch.
    @Test func aPieceDeletedForGoodStaysGone() async throws {
        let store = try TemporaryStore("purge")
        let tee = try #require(Self.demo.garments.first { $0.id == "g-black-tee" })
        do {
            let storage = try store.open()
            try await storage.closet.save(tee)
            try await storage.closet.delete(tee.id, at: TestTime.now)
            try await storage.closet.deletePermanently(tee.id)
        }
        let relaunched = try store.open()
        await #expect(throws: StoreError.notFound) { try await relaunched.closet.garment(tee.id) }
    }

    /// Delete my data through every store leaves no record of hers in the file, and a relaunch
    /// finds a fresh install. Only the content-free note that the old suite was moved in stays.
    @Test func deleteMyDataLeavesNothing() async throws {
        let store = try TemporaryStore("delete")
        let storage = try store.open()
        let suite = AppStateDefaultsTests.Suite()
        AppStateDefaultsImport.run(suiteName: suite.name, into: storage.container)
        for garment in Self.demo.garments { try await storage.closet.save(garment) }
        for look in Self.demo.looks { try await storage.looks.save(look) }
        for suitcase in Self.demo.suitcases { try await storage.suitcases.restore(suitcase) }
        for picture in Self.demo.pictures { try await storage.pictures.save(picture) }
        try await storage.profile.save(Self.demo.profile)
        try await storage.lookDrafts.save(LookDraft(name: "Pink", savedAt: TestTime.now))
        try await storage.feedbackDrafts.save(FeedbackDraft(message: "Hello"))
        try await storage.onboarding.complete(startingCloset: .empty)
        try await storage.tours.setShowsTipsOnNewScreens(false)

        let deletion = LocalDataDeletion(
            stores: storage.erasableData + [(.profile, storage.tours), (.profile, storage.onboarding)])
        #expect(await deletion.delete(.thisDevice).isComplete)

        let kinds = try ModelContext(storage.container).fetch(FetchDescriptor<StoredRecord>()).map(\.kind)
        #expect(kinds == [RecordKind.defaultsImport.rawValue])
        let relaunched = try store.open()
        #expect(try await relaunched.closet.garments().isEmpty)
        #expect(try await relaunched.profile.profile() == Profile())
        #expect(try await relaunched.onboarding.state() == .fresh)
        #expect(try await relaunched.tours.progress() == .fresh)
    }

    /// The store and its folder ask for Data Protection `complete`. The simulator doesn't keep
    /// protection classes (it reports none), so this can only fail on a class other than
    /// `complete`; the device check is listed in docs/models.md.
    @Test func theStoreFilesAskForCompleteProtection() async throws {
        let store = try TemporaryStore("protection")
        let storage = try store.open()
        try await storage.profile.save(Profile(signName: "Lily"))
        for url in [store.location.directory] + store.location.storeFiles
        where FileManager.default.fileExists(atPath: url.path) {
            let protection = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey]
            #expect(
                protection == nil || protection as? FileProtectionType == .complete, "\(url.lastPathComponent)")
        }
    }

    /// The store never asks for CloudKit: sync will be `CKSyncEngine`'s, never SwiftData's own.
    @Test func theStoreDoesNotSyncWithCloudKit() throws {
        let store = try TemporaryStore("cloudkit")
        let storage = try store.open()
        #expect(storage.container.configurations.allSatisfy { "\($0.cloudKitDatabase)".contains("none") })
        #expect(storage.container.configurations.first?.url == store.location.storeURL)
    }
}
