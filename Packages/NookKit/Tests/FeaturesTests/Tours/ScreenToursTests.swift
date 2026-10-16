import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Phase 16b (PRD §7.8, FR-73): every screen's tour, first use, the tips switch, Reset all tips,
/// replay from App tours, and only one tour at a time.
@MainActor
struct ScreenToursTests {
    nonisolated static let date = Date(timeIntervalSince1970: 1_800_000_000)

    /// Every tour in the app, in each of its forms.
    static var definitions: [TourDefinition] {
        [
            HomeTour.definition(for: .phoneRoom), HomeTour.definition(for: .iPadRoom),
            HomeTour.definition(for: .largeText), HomeTour.definition(for: .sideways),
            ClosetTour.definition(detailBeside: false), ClosetTour.definition(detailBeside: true),
            GarmentTour.definition, AddPieceTour.definition, StyleMeTour.definition,
            YourLooksTour.definition(hasVersions: true), YourLooksTour.definition(hasVersions: false),
            SwapTour.definition, LookBuilderTour.definition, SavedLooksTour.definition, LookTour.definition,
            PictureTour.definition, SuitcasesTour.definition, SuitcaseTour.definition(hasPieces: true),
            SuitcaseTour.definition(hasPieces: false), LaundryTour.definition(hasScope: true),
            LaundryTour.definition(hasScope: false), LaundryTour.offDefinition, ProfileTour.definition,
            FitTour.definition, HelpTour.definition, FeedbackTour.definition, PrivacyTour.definition,
        ]
    }

    private func center(
        _ store: InMemoryTourProgressStore = InMemoryTourProgressStore(), launch: TourLaunchOptions = .standard
    ) -> TourCenter {
        TourCenter(store: store, launch: launch, now: { Self.date })
    }

    // MARK: The tours

    @Test func everyScreenHasAShortTourWithItsOwnControls() {
        for definition in Self.definitions {
            #expect((2...4).contains(definition.steps.count), "\(definition.id)")
            #expect(Set(definition.steps.map(\.anchor)).count == definition.steps.count, "\(definition.id)")
            #expect(definition.steps.allSatisfy { !$0.title.isEmpty && !$0.message.isEmpty }, "\(definition.id)")
            #expect(definition.version == 1)
            if definition.id != .home {
                #expect(definition.finishTitle == "Got it", "\(definition.id)")
            }
        }
        #expect(Set(Self.definitions.map(\.id)) == Set(TourID.all))
    }

    @Test func layoutsOfAScreenShareItsTourAndStepCount() {
        // Rotating, resizing or changing the text size keeps the step (`TourCenter.update`).
        #expect(ClosetTour.definition(detailBeside: true).steps.count == 3)
        #expect(ClosetTour.definition(detailBeside: false).steps.count == 3)
        #expect(ClosetTour.definition(detailBeside: true).steps.last?.anchor == ClosetTour.Anchor.beside)
    }

    /// Copy that follows Lily's sign-off and the amendment, not the older mockups.
    @Test func theWordsFollowTheApprovedChanges() {
        let words = Self.definitions.flatMap { $0.steps.map { "\($0.title) \($0.message)" } }.joined(separator: " ")
        for outdated in ["Shuffle", "Mode", "fit reference", "Tap Edit to change the pieces", "pretend", "preview"] {
            #expect(!words.contains(outdated), "\(outdated)")
        }
        #expect(
            LookBuilderTour.definition.steps[0].message.hasPrefix("Build an outfit yourself, piece by piece."))
        #expect(FitTour.definition.steps[0].message.contains("saved until you change it"))
        #expect(FitTour.definition.steps.contains { $0.title == "Add a piece that fits you well" })
        #expect(YourLooksTour.definition(hasVersions: true).steps[0].message.contains("Simple, Dressed up"))
    }

    // MARK: App tours

    @Test func appToursListsEveryTourOnceWithItsTipCount() {
        let entries = TourCatalog.entries
        #expect(entries.map(\.id) == TourID.all)
        #expect(
            entries.filter(\.isCommon).map(\.id) == [
                .home, .closet, .styleMe, .yourLooks, .savedLooks, .suitcases, .fit,
            ])
        for entry in entries {
            let most = Self.definitions.filter { $0.id == entry.id }.map(\.steps.count).max()
            #expect(entry.stepCount == most, "\(entry.id)")
            #expect(entry.detail.hasPrefix("\(entry.stepCount) quick tips · "), "\(entry.id)")
        }
        // Laundry's tour for the way tracking is set.
        #expect(TourCatalog.entries(tracksLaundry: true).contains { $0.id == .laundry })
        #expect(!TourCatalog.entries(tracksLaundry: true).contains { $0.id == .laundryOff })
        #expect(TourCatalog.entries(tracksLaundry: false).contains { $0.id == .laundryOff })
        #expect(!TourCatalog.entries(tracksLaundry: false).contains { $0.id == .laundry })
    }

    // MARK: First use

    @Test func eachScreenShowsItsTourOnceOnAFreshInstall() async throws {
        let store = InMemoryTourProgressStore()
        let tours = center(store)
        for definition in [ClosetTour.definition(detailBeside: false), GarmentTour.definition, StyleMeTour.definition] {
            #expect(await tours.startIfNeeded(definition), "\(definition.id)")
            tours.skip()
            #expect(await !tours.startIfNeeded(definition), "\(definition.id) came back")
        }
        await tours.lastWrite?.value
        // A new launch over the same store: seen stays seen.
        #expect(await !center(store).startIfNeeded(GarmentTour.definition))
        #expect(try await store.progress().records.count == 3)
    }

    @Test func neverTwoToursAtOnce() async {
        let tours = center()
        #expect(await tours.startIfNeeded(ClosetTour.definition(detailBeside: true)))
        // The piece beside the grid asks while Closet's tour shows: it waits.
        #expect(await !tours.startIfNeeded(GarmentTour.definition))
        #expect(tours.active?.definition.id == .closet)
        tours.skip()
        // Once Closet's has ended it can start, since it hasn't shown yet.
        #expect(await tours.startIfNeeded(GarmentTour.definition))
    }

    @Test func tipsOffStopsEveryTourStartingByItself() async throws {
        let store = InMemoryTourProgressStore()
        let tours = center(store)
        #expect(await tours.setShowsTips(false))
        #expect(await tours.showsTips() == false)
        for definition in Self.definitions {
            #expect(await !tours.startIfNeeded(definition), "\(definition.id)")
        }
        #expect(await tours.setShowsTips(true))
        #expect(await tours.startIfNeeded(SwapTour.definition))
    }

    @Test func theDebugFlagIsAppliedBeforeAnyScreenReadsTheStore() async {
        // Two screens asking at once at launch: neither may read the store before `-tour off`.
        let tours = center(launch: TourLaunchOptions(turnsTipsOff: true))
        async let first = tours.startIfNeeded(HomeTour.definition(for: .phoneRoom))
        async let second = tours.startIfNeeded(ClosetTour.definition(detailBeside: false))
        let started = await [first, second]
        #expect(started == [false, false])
    }

    @Test func theFlagTakesAnyTour() {
        let options = TourLaunchOptions(launchArguments: ["-tour", "reset,closet,yourLooks,nonsense"])
        #expect(options.startsTours == [.closet, .yourLooks])
        #expect(options.resetsProgress)
    }

    // MARK: Replay and reset

    @Test func replayStartsASeenTourFromStepOneEvenWithTipsOff() async throws {
        var seen = TourProgress(showsTipsOnNewScreens: false)
        seen.add(TourRecord(tour: .laundry, version: 1, outcome: .finished, date: Self.date))
        let tours = center(InMemoryTourProgressStore(progress: seen))
        let laundry = LaundryTour.definition(hasScope: true)
        #expect(await !tours.startIfNeeded(laundry))

        tours.replay(.laundry)
        #expect(tours.isWaiting(.laundry))
        // Not until the screen is ready, and the replay keeps waiting meanwhile.
        #expect(await !tours.startIfNeeded(laundry) { false })
        #expect(tours.isWaiting(.laundry))
        // Another screen's tour doesn't use it up.
        #expect(await !tours.startIfNeeded(HelpTour.definition))
        #expect(await tours.startIfNeeded(laundry))
        #expect(tours.active?.run.index == 0)
        #expect(!tours.isWaiting(.laundry))
        tours.skip()
        // Once only.
        #expect(await !tours.startIfNeeded(laundry))
    }

    @Test func replayingTheSameTourAgainInOneSession() async {
        let tours = center()
        #expect(await tours.startIfNeeded(ProfileTour.definition))
        tours.next()
        tours.skip()
        tours.replay(.profile)
        #expect(await tours.startIfNeeded(ProfileTour.definition))
        #expect(tours.active?.run.index == 0)
    }

    @Test func resetAllTipsShowsEachTourAgain() async throws {
        let store = InMemoryTourProgressStore()
        let tours = center(store)
        await tours.startIfNeeded(PictureTour.definition)
        tours.skip()
        await tours.lastWrite?.value
        #expect(await !tours.startIfNeeded(PictureTour.definition))

        #expect(await tours.resetAllTips())
        #expect(try await store.progress().records.isEmpty)
        // Even this session, the next time the screen opens.
        #expect(await tours.startIfNeeded(PictureTour.definition))
    }

    /// Profile opens App tours: turning tips on or resetting them there doesn't start Profile's
    /// own tour as the sheet closes, but a replay does.
    @Test func theScreenThatOpensAppToursIsHeldBack() async {
        let tours = center()
        tours.holdBack(.profile)
        #expect(await !tours.startIfNeeded(ProfileTour.definition))
        #expect(await tours.startIfNeeded(HelpTour.definition))
        tours.skip()
        await tours.lastWrite?.value
        #expect(await tours.resetAllTips(keeping: [.profile]))
        #expect(await !tours.startIfNeeded(ProfileTour.definition))
        // Help showed this session, and Reset all tips lets it show again.
        #expect(await tours.startIfNeeded(HelpTour.definition))
        tours.skip()
        tours.replay(.profile)
        #expect(await tours.startIfNeeded(ProfileTour.definition))
    }

    @Test func aStoreThatFailsSaysSo() async {
        let tours = center(InMemoryTourProgressStore(options: StoreOptions(fails: true)))
        #expect(await tours.showsTips() == nil)
        #expect(await !tours.setShowsTips(false))
        #expect(await !tours.resetAllTips())
        // Replay never needs the store.
        tours.replay(.help)
        #expect(await tours.startIfNeeded(HelpTour.definition))
    }

    @Test func deleteMyDataForgetsAWaitingReplay() async {
        let tours = center()
        tours.replay(.swap)
        tours.forgetSession()
        #expect(!tours.isWaiting(.swap))
    }
}
