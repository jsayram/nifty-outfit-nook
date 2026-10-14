import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// What the room says and where each piece goes (RD-01, RD-03, RD-10, RD-11).
struct RoomControlTests {
    @Test func furnitureOpensItsScreen() {
        let routes = Dictionary(uniqueKeysWithValues: RoomControl.allCases.map { ($0, $0.route(hamper: .allClean)) })
        #expect(routes[.wardrobe] == .tab(.closet))
        #expect(routes[.savedLooks] == .tab(.savedLooks))
        #expect(routes[.nameSign] == .push(.profile))
        #expect(routes[.laptop] == .push(.styleMe(choosingOccasion: false)))
        #expect(routes[.occasion] == .push(.styleMe(choosingOccasion: true)))
        #expect(routes[.helpDrawer] == .push(.help))
        #expect(routes[.feedbackDrawer] == .push(.feedback))
        #expect(routes[.privacyDrawer] == .push(.privacy))
        #expect(routes[.suitcase] == .push(.suitcases))
        #expect(routes[.hamper] == .push(.laundry))
    }

    /// RD-11.3: Laundry when tracking is on, the short sheet about it when it's off. Before the
    /// closet loads it opens Laundry rather than claim tracking is off.
    @Test func hamperFollowsLaundryTracking() {
        #expect(RoomControl.hamper.route(hamper: .toWash(2)) == .push(.laundry))
        #expect(RoomControl.hamper.route(hamper: .allClean) == .push(.laundry))
        #expect(RoomControl.hamper.route(hamper: .off) == .sheet(.laundryTracking))
        #expect(RoomControl.hamper.route(hamper: nil) == .push(.laundry))
    }

    /// RD-01.2 and RD-10.2: each label names the object and where it goes.
    @Test func labelsNameTheirDestination() {
        let content = HomeRoomContent(
            signName: "Lily", source: SourcePlate(kind: .mainCloset, pieceCount: 17), hamper: .toWash(2))
        let labels = Dictionary(
            uniqueKeysWithValues: RoomControl.allCases.map { ($0, $0.accessibilityLabel(for: content)) })
        #expect(labels[.wardrobe] == "Wardrobe: Closet")
        #expect(labels[.laptop] == "Laptop: Style Me")
        #expect(labels[.helpDrawer] == "Top drawer: Help")
        #expect(labels[.feedbackDrawer] == "Middle drawer: Send feedback")
        #expect(labels[.privacyDrawer] == "Bottom drawer: Privacy and terms")
        #expect(labels[.nameSign] == "Name sign: Lily")
        #expect(labels[.suitcase] == "Suitcase: Source, Main closet, 17 pieces, Whole closet")
        #expect(labels[.hamper] == "Hamper: Laundry, 2 to wash")
        for control in RoomControl.allCases {
            #expect(!control.accessibilityHint(for: content).isEmpty)
        }
    }

    @Test func emptyNameSignIsReadAsHavingNoName() {
        #expect(
            RoomControl.nameSign.accessibilityLabel(for: HomeRoomContent(signName: "  ")) == "Name sign, no name yet")
    }

    @Test func readingOrderFollowsTheCaseOrder() {
        let priorities = RoomControl.allCases.map(\.sortPriority)
        #expect(priorities == priorities.sorted(by: >))
        #expect(Set(priorities).count == priorities.count)
        #expect(Set(RoomControl.allCases.map(\.identifier)).count == RoomControl.allCases.count)
    }
}

struct HomeRoomContentTests {
    /// RD-03.2: an empty name never leaves the sign blank.
    @Test func signFallsBackToANeutralWord() {
        #expect(SignName.shown("Lily") == "Lily")
        #expect(SignName.shown("  Lily ") == "Lily")
        #expect(SignName.shown("") == "Hello")
        #expect(SignName.shown(" \n") == "Hello")
    }

    @Test func sourcePlateWords() {
        #expect(SourcePlate(kind: .mainCloset, pieceCount: 17).countText == "17 pieces")
        #expect(SourcePlate(kind: .mainCloset, pieceCount: 1).countText == "1 piece")
        #expect(SourcePlate(kind: .mainCloset, pieceCount: 0).countText == "Empty")
        #expect(SourcePlate(kind: .mainCloset).countText == nil)
        #expect(SourcePlate(kind: .mainCloset).name == "Main closet")
        #expect(SourcePlate(kind: .mainCloset).scopeText == "Whole closet")
        #expect(SourcePlate(kind: .suitcase(name: "Jose’s house")).name == "Jose’s house")
        #expect(SourcePlate(kind: .suitcase(name: "Jose’s house")).scopeText == "Suitcase only")
    }

    @Test func hamperPlateWords() {
        #expect(HamperState.off.plateText == "Off")
        #expect(HamperState.allClean.plateText == "All clean")
        #expect(HamperState.toWash(2).plateText == "2 to wash")
    }
}

@MainActor
struct HomeModelTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func demoClosetFillsTheRoom() async {
        let model = HomeModel()
        await model.load(from: FixtureServices.make(set: .demo, now: now))
        #expect(model.phase == .loaded)
        #expect(model.content.signName == "Lily")
        #expect(model.content.source.kind == .mainCloset)
        #expect(model.content.source.pieceCount == 17)
        // Lily's default has laundry tracking off (RD-11).
        #expect(model.content.hamper == .off)
    }

    @Test func emptyClosetShowsTheFallbacks() async {
        let model = HomeModel()
        await model.load(from: FixtureServices.make(set: .empty, now: now))
        #expect(model.phase == .loaded)
        #expect(model.content.signName == "")
        #expect(model.content.source.countText == "Empty")
        #expect(model.content.hamper == .off)
    }

    /// RD-01.3: the plate shows a suitcase source's name and count.
    @Test func suitcaseSourceShowsItsNameAndCount() async throws {
        let services = FixtureServices.make(set: .demo, now: now)
        let suitcase = try #require(
            try await services.suitcases.suitcases().first { !$0.isArchived && !$0.garmentIDs.isEmpty })
        let model = HomeModel()
        model.source = .suitcase(suitcase.id)
        await model.load(from: services)
        #expect(model.content.source.kind == .suitcase(name: suitcase.name))
        let expected = try await services.closet.garments().count { $0.isInCloset && suitcase.contains($0.id) }
        #expect(model.content.source.pieceCount == expected)
        #expect(model.content.source.scopeText == "Suitcase only")
    }

    /// A failing store leaves a working room with honest plates.
    @Test func failingStoresStillLeaveAWorkingRoom() async {
        let model = HomeModel()
        await model.load(from: FixtureServices.make(set: .demo, behavior: .storesFail, now: now))
        #expect(model.phase == .failed)
        #expect(model.content.signName == "")
        #expect(model.content.source.pieceCount == nil)
        #expect(model.content.hamper == nil)
    }

    @Test func noServicesMeansNothingToLoad() async {
        let model = HomeModel()
        await model.load(from: nil)
        #expect(model.phase == .loaded)
        #expect(model.content.signName == nil)
    }
}
