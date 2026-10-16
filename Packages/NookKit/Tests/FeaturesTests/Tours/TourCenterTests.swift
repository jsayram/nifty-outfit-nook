import CoreGraphics
import Fixtures
import Foundation
import Models
import SwiftUI
import Testing

@testable import Features

/// Running a tour (Phase 16a, PRD §7.8): when it starts, how the buttons move through it, and
/// what's recorded when it ends.
@MainActor
struct TourCenterTests {
    nonisolated static let date = Date(timeIntervalSince1970: 1_800_000_000)
    let tour = HomeTour.definition(for: .phoneRoom)

    private func center(
        _ store: InMemoryTourProgressStore = InMemoryTourProgressStore(), launch: TourLaunchOptions = .standard
    ) -> TourCenter {
        TourCenter(store: store, launch: launch, now: { Self.date })
    }

    @Test func homeHasFourStepsInTheApprovedOrder() {
        for variant in [HomeTour.Variant.phoneRoom, .iPadRoom, .largeText, .sideways] {
            let steps = HomeTour.definition(for: variant).steps
            #expect(
                steps.map(\.anchor)
                    == [
                        HomeTour.Anchor.styleMe, HomeTour.Anchor.closet, HomeTour.Anchor.source,
                        HomeTour.Anchor.profile,
                    ])
            #expect(HomeTour.definition(for: variant).id == .home)
        }
        #expect(tour.finishTitle == "Start styling")
    }

    @Test func startsOnceOnAFreshInstall() async {
        let tours = center()
        #expect(await tours.startIfNeeded(tour))
        #expect(tours.active?.run.index == 0)
        #expect(tours.currentAnchor == HomeTour.Anchor.styleMe)
        // Already showing, then already started this session: never twice.
        #expect(await !tours.startIfNeeded(tour))
        tours.skip()
        #expect(await !tours.startIfNeeded(tour))
    }

    @Test func nextWalksTheStepsAndTheLastButtonFinishes() async throws {
        let store = InMemoryTourProgressStore()
        let tours = center(store)
        await tours.startIfNeeded(tour)
        tours.next()
        tours.next()
        #expect(tours.currentAnchor == HomeTour.Anchor.source)
        tours.back()
        #expect(tours.currentAnchor == HomeTour.Anchor.closet)
        tours.next()
        tours.next()
        #expect(tours.active?.run.isLastStep == true)
        tours.next()
        #expect(tours.active == nil)
        // Start styling sends VoiceOver to Style Me.
        #expect(tours.focusRequest?.anchor == HomeTour.Anchor.styleMe)
        await tours.lastWrite?.value
        let record = try #require(try await store.progress().records[.home])
        #expect(record == TourRecord(tour: .home, version: HomeTour.version, outcome: .finished, date: Self.date))
    }

    @Test func skipRecordsItAsSeenAndReturnsFocusToTheStepControl() async throws {
        let store = InMemoryTourProgressStore()
        let tours = center(store)
        await tours.startIfNeeded(tour)
        tours.next()
        tours.skip()
        #expect(tours.active == nil)
        #expect(tours.focusRequest?.anchor == HomeTour.Anchor.closet)
        await tours.lastWrite?.value
        #expect(try await store.progress().records[.home]?.outcome == .skipped)

        // A new launch (a new center over the same store) doesn't show it again.
        #expect(await !center(store).startIfNeeded(tour))
    }

    @Test func tappingTheHighlightedControlEndsTheTourThenRunsItOnce() async throws {
        let store = InMemoryTourProgressStore()
        let tours = center(store)
        var opened: [String] = []
        let owner = UUID()
        tours.register(HomeTour.Anchor.styleMe, owner: owner, label: "Laptop: Style Me", hint: nil) {
            // The tour has already gone when the control acts.
            opened.append(tours.isShowing ? "under the tour" : "Style Me")
        }
        await tours.startIfNeeded(tour)
        tours.activateTarget()
        #expect(opened == ["Style Me"])
        #expect(tours.active == nil)
        tours.activateTarget()
        #expect(opened == ["Style Me"])
        await tours.lastWrite?.value
        #expect(try await store.progress().records[.home]?.outcome == .controlActivated)
    }

    @Test func doesNotStartWhileTipsAreOffOrOnceSeen() async throws {
        let off = InMemoryTourProgressStore(progress: TourProgress(showsTipsOnNewScreens: false))
        #expect(await !center(off).startIfNeeded(tour))

        var seen = TourProgress.fresh
        seen.add(TourRecord(tour: .home, version: HomeTour.version, outcome: .finished, date: Self.date))
        #expect(await !center(InMemoryTourProgressStore(progress: seen)).startIfNeeded(tour))
    }

    @Test func aStoreThatCannotBeReadMeansNoTour() async {
        let failing = InMemoryTourProgressStore(options: StoreOptions(fails: true))
        #expect(await !center(failing).startIfNeeded(tour))
        #expect(await !TourCenter(store: nil).startIfNeeded(tour))
    }

    @Test func waitsUntilTheScreenIsReady() async {
        let tours = center()
        #expect(await !tours.startIfNeeded(tour, when: { false }))
        #expect(tours.active == nil)
        #expect(await tours.startIfNeeded(tour, when: { true }))
    }

    @Test func theDebugFlag() async throws {
        // `-tour home` starts it once whatever is recorded, even with tips off.
        var seen = TourProgress(showsTipsOnNewScreens: false)
        seen.add(TourRecord(tour: .home, version: HomeTour.version, outcome: .skipped, date: Self.date))
        let forced = center(
            InMemoryTourProgressStore(progress: seen), launch: TourLaunchOptions(startsTours: [.home]))
        #expect(await forced.startIfNeeded(tour))

        // `-tour off` turns tips off before anything starts.
        let offStore = InMemoryTourProgressStore()
        #expect(await !center(offStore, launch: TourLaunchOptions(turnsTipsOff: true)).startIfNeeded(tour))
        #expect(try await !offStore.progress().showsTipsOnNewScreens)

        // `-tour reset` forgets what was seen and turns tips back on.
        let resetStore = InMemoryTourProgressStore(progress: seen)
        #expect(await center(resetStore, launch: TourLaunchOptions(resetsProgress: true)).startIfNeeded(tour))
    }

    @Test func theFlagIsReadFromTheLaunchArguments() {
        #expect(TourLaunchOptions(launchArguments: []) == .standard)
        #expect(TourLaunchOptions(launchArguments: ["-tour", "home"]).startsTours == [.home])
        let both = TourLaunchOptions(launchArguments: ["-fixtures", "demo", "-tour", "reset,off,nonsense"])
        #expect(both.resetsProgress && both.turnsTipsOff && both.startsTours.isEmpty)
        #expect(TourLaunchOptions(launchArguments: ["-tour"]) == .standard)
    }

    @Test func aNewLayoutKeepsTheStepWithItsOwnWords() async {
        let tours = center()
        await tours.startIfNeeded(tour)
        tours.next()
        tours.update(HomeTour.definition(for: .largeText))
        #expect(tours.active?.run.index == 1)
        #expect(tours.active?.definition == HomeTour.definition(for: .largeText))
        // Another tour's words never replace this one's.
        var other = tour
        other.id = TourID("closet")
        tours.update(other)
        #expect(tours.active?.definition.id == .home)
    }

    @Test func afterDeleteMyDataItCanStartAgain() async {
        let tours = center()
        await tours.startIfNeeded(tour)
        tours.skip()
        await tours.lastWrite?.value
        // Delete my data erases the store and the session.
        tours.forgetSession()
        let fresh = TourCenter(store: InMemoryTourProgressStore())
        #expect(await fresh.startIfNeeded(tour))
    }

    @Test func anchorsFollowTheirViewAndOnlyTheirOwnerRemovesThem() {
        let tours = center()
        let room = UUID()
        let largeText = UUID()
        tours.register(HomeTour.Anchor.closet, owner: room, label: "Wardrobe: Closet", hint: nil, action: nil)
        tours.move(HomeTour.Anchor.closet, owner: room, to: CGRect(x: 0, y: 100, width: 170, height: 420))
        #expect(tours.anchors[HomeTour.Anchor.closet]?.frame?.height == 420)

        // The large-text banner takes over the anchor; the room leaving afterwards doesn't remove it.
        tours.register(HomeTour.Anchor.closet, owner: largeText, label: "Wardrobe: Closet", hint: nil, action: nil)
        tours.move(HomeTour.Anchor.closet, owner: room, to: .zero)
        tours.remove(HomeTour.Anchor.closet, owner: room)
        #expect(tours.anchors[HomeTour.Anchor.closet]?.owner == largeText)
        #expect(tours.anchors[HomeTour.Anchor.closet]?.frame == nil)
        tours.remove(HomeTour.Anchor.closet, owner: largeText)
        #expect(tours.anchors[HomeTour.Anchor.closet] == nil)
    }

    /// A control that's off screen or under a bar gets no spotlight; the card shows alone.
    @Test func aControlOutOfSightGetsNoSpotlight() {
        let size = CGSize(width: 402, height: 874)
        let insets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        let laptop = CGRect(x: 230, y: 440, width: 90, height: 64)
        #expect(TourOverlay.visible(laptop, in: size, insets: insets) == laptop)
        // Below the screen, or tucked under the status bar.
        #expect(TourOverlay.visible(laptop.offsetBy(dx: 0, dy: 800), in: size, insets: insets) == nil)
        #expect(TourOverlay.visible(CGRect(x: 20, y: 40, width: 80, height: 30), in: size, insets: insets) == nil)
        // A tall wardrobe running off the left edge still counts.
        let wardrobe = CGRect(x: -12, y: 240, width: 177, height: 425)
        #expect(TourOverlay.visible(wardrobe, in: size, insets: insets) == wardrobe)
    }
}
