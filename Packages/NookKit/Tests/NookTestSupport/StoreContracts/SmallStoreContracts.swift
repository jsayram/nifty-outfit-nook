import Foundation
import Models
import Testing

/// What every `TryOnPictureStore` does. See `StoreContract.swift` for how to run it.
public struct TryOnPictureStoreContract: Sendable {
    /// Makes a store holding these pictures.
    public typealias Factory = @Sendable ([TryOnPicture]) async throws -> any TryOnPictureStore

    public enum Check: String, CaseIterable, Sendable {
        case listsNewestFirst
        case readsOneOrNotFound
        case saveKeepsAndPutsBack
        case deleteRemovesIt
        case eraseAllEmptiesIt
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    private static func picture(_ id: TryOnPicture.ID, daysAgo: Int) -> TryOnPicture {
        TryOnPicture(
            id: id, of: ContractData.look("l1", name: "Office navy"), image: .simulated,
            createdAt: TestTime.day(-daysAgo))
    }

    public func run(_ check: Check) async throws {
        let older = Self.picture("p-older", daysAgo: 3)
        let newer = Self.picture("p-newer", daysAgo: 1)
        let store = try await make([older, newer])

        switch check {
        case .listsNewestFirst:
            #expect(try await store.pictures().map(\.id) == ["p-newer", "p-older"])

        case .readsOneOrNotFound:
            #expect(try await store.picture("p-older") == older)
            #expect(await storeError { try await store.picture("nope") } == .notFound)

        case .saveKeepsAndPutsBack:
            let made = Self.picture("p-new", daysAgo: 0)
            try await store.save(made)
            #expect(try await store.pictures().map(\.id) == ["p-new", "p-newer", "p-older"])
            try await store.delete("p-older")
            try await store.save(older)
            #expect(try await store.picture("p-older") == older)

        case .deleteRemovesIt:
            try await store.delete("p-older")
            #expect(try await store.pictures().map(\.id) == ["p-newer"])
            #expect(await storeError { try await store.delete("p-older") } == .notFound)

        case .eraseAllEmptiesIt:
            try await store.eraseAll()
            #expect(try await store.pictures().isEmpty)
            try await store.eraseAll()
        }
    }
}

/// What every `DraftStore` does. See `StoreContract.swift` for how to run it.
public struct DraftStoreContract: Sendable {
    /// Makes a store holding these drafts.
    public typealias Factory = @Sendable ([GarmentDraft]) async throws -> any DraftStore

    public enum Check: String, CaseIterable, Sendable {
        case listsMostRecentFirst
        case oneDraftPerTarget
        case discardRemovesOnlyThatTarget
        case eraseAllEmptiesIt
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    private static func draft(_ target: GarmentDraft.Target, name: String, daysAgo: Int) -> GarmentDraft {
        GarmentDraft(
            target: target, step: .details, details: GarmentDetails(name: name), base: GarmentDetails(),
            savedAt: TestTime.day(-daysAgo))
    }

    public func run(_ check: Check) async throws {
        let newPiece = Self.draft(.newPiece, name: "Sage cardigan", daysAgo: 2)
        let edit = Self.draft(.garment("g1"), name: "Navy trousers", daysAgo: 1)
        let store = try await make([newPiece, edit])

        switch check {
        case .listsMostRecentFirst:
            #expect(try await store.drafts() == [edit, newPiece])

        case .oneDraftPerTarget:
            #expect(try await store.draft(for: .newPiece) == newPiece)
            #expect(try await store.draft(for: .garment("g2")) == nil)
            let later = Self.draft(.newPiece, name: "Sage cardigan, long", daysAgo: 0)
            try await store.save(later)
            #expect(try await store.draft(for: .newPiece) == later)
            #expect(try await store.drafts() == [later, edit])

        case .discardRemovesOnlyThatTarget:
            try await store.discard(.newPiece)
            #expect(try await store.drafts() == [edit])
            // Discarding one that isn't there is fine.
            try await store.discard(.newPiece)
            try await store.discard(.garment("g2"))
            #expect(try await store.drafts() == [edit])

        case .eraseAllEmptiesIt:
            try await store.eraseAll()
            #expect(try await store.drafts().isEmpty)
            try await store.eraseAll()
        }
    }
}

/// What every `LookDraftStore` does. See `StoreContract.swift` for how to run it.
public struct LookDraftStoreContract: Sendable {
    /// Makes a store holding this draft, or none.
    public typealias Factory = @Sendable (LookDraft?) async throws -> any LookDraftStore

    public enum Check: String, CaseIterable, Sendable {
        case startsWithWhatItWasGiven
        case saveReplacesTheDraft
        case discardRemovesIt
        case eraseAllRemovesIt
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    public func run(_ check: Check) async throws {
        let draft = LookDraft(name: "Rainy office", garmentIDs: ["g1", "g2"], savedAt: TestTime.day(-1))

        switch check {
        case .startsWithWhatItWasGiven:
            #expect(try await make(nil).draft() == nil)
            #expect(try await make(draft).draft() == draft)

        case .saveReplacesTheDraft:
            let store = try await make(nil)
            try await store.save(draft)
            #expect(try await store.draft() == draft)
            let later = LookDraft(garmentIDs: ["g3"], startingPieceID: "g3", savedAt: TestTime.now)
            try await store.save(later)
            #expect(try await store.draft() == later)

        case .discardRemovesIt:
            let store = try await make(draft)
            try await store.discard()
            #expect(try await store.draft() == nil)
            // Discarding when there's none is fine.
            try await store.discard()

        case .eraseAllRemovesIt:
            let store = try await make(draft)
            try await store.eraseAll()
            #expect(try await store.draft() == nil)
            try await store.eraseAll()
        }
    }
}

/// What every `TourProgressStore` does. See `StoreContract.swift` for how to run it.
public struct TourProgressStoreContract: Sendable {
    /// Makes an empty store, as on a fresh install.
    public typealias Factory = @Sendable () async throws -> any TourProgressStore

    public enum Check: String, CaseIterable, Sendable {
        case startsFresh
        case recordKeepsTheHighestVersionSeen
        case switchIsKept
        case forgetSeenToursKeepsTheSwitch
        case eraseAllIsAFreshInstall
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    public func run(_ check: Check) async throws {
        let store = try await make()
        let finished = TourRecord(tour: .home, version: 2, outcome: .finished, date: TestTime.now)

        switch check {
        case .startsFresh:
            let progress = try await store.progress()
            #expect(progress.seenVersions.isEmpty)
            #expect(progress.records.isEmpty)
            #expect(progress.showsTipsOnNewScreens)

        case .recordKeepsTheHighestVersionSeen:
            try await store.record(finished)
            try await store.record(TourRecord(tour: .home, version: 1, outcome: .skipped, date: TestTime.now))
            try await store.record(TourRecord(tour: .closet, version: 1, outcome: .skipped, date: TestTime.now))
            let progress = try await store.progress()
            #expect(progress.seenVersions == [.home: 2, .closet: 1])
            #expect(progress.records[.home]?.outcome == .skipped)
            #expect(!TourRules.startsAutomatically(.home, version: 2, progress: progress))
            #expect(TourRules.startsAutomatically(.home, version: 3, progress: progress))

        case .switchIsKept:
            try await store.setShowsTipsOnNewScreens(false)
            #expect(try await store.progress().showsTipsOnNewScreens == false)
            try await store.setShowsTipsOnNewScreens(true)
            #expect(try await store.progress().showsTipsOnNewScreens)

        case .forgetSeenToursKeepsTheSwitch:
            try await store.record(finished)
            try await store.setShowsTipsOnNewScreens(false)
            try await store.forgetSeenTours()
            let progress = try await store.progress()
            #expect(progress.seenVersions.isEmpty)
            #expect(progress.records.isEmpty)
            #expect(progress.showsTipsOnNewScreens == false)

        case .eraseAllIsAFreshInstall:
            try await store.record(finished)
            try await store.setShowsTipsOnNewScreens(false)
            try await store.eraseAll()
            #expect(try await store.progress() == .fresh)
            try await store.eraseAll()
        }
    }
}

/// What every `OnboardingStateStore` does. See `StoreContract.swift` for how to run it.
public struct OnboardingStateStoreContract: Sendable {
    /// Makes an empty store, as on a fresh install.
    public typealias Factory = @Sendable () async throws -> any OnboardingStateStore

    public enum Check: String, CaseIterable, Sendable {
        case startsFresh
        case completeKeepsTheStartingCloset
        case eraseAllIsAFreshInstall
    }

    private let make: Factory

    public init(make: @escaping Factory) {
        self.make = make
    }

    public func run(_ check: Check) async throws {
        let store = try await make()

        switch check {
        case .startsFresh:
            #expect(try await store.state() == .fresh)

        case .completeKeepsTheStartingCloset:
            try await store.complete(startingCloset: .empty)
            #expect(try await store.state() == OnboardingState(isCompleted: true, startingCloset: .empty))
            try await store.complete(startingCloset: .sample)
            #expect(try await store.state() == OnboardingState(isCompleted: true, startingCloset: .sample))

        case .eraseAllIsAFreshInstall:
            try await store.complete(startingCloset: .sample)
            try await store.eraseAll()
            #expect(try await store.state() == .fresh)
            try await store.eraseAll()
        }
    }
}
