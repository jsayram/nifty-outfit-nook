import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// The source and occasion Style Me remembers (FR-67, Phase 13), and where they show.
@MainActor
struct RememberedChoicesTests {
    private let now = ClosetTestTime.now

    private func services(source: FixtureSourceState? = nil) -> NookServices {
        FixtureServices.make(set: .demo, source: source, now: now, calendar: ClosetTestTime.calendar)
    }

    @Test func styleMeStartsFromTheRememberedSourceAndOccasion() async throws {
        let services = services(source: .suitcase)
        try await services.profile.change { $0.remembered.occasion = .brunch }
        let model = StyleMeModel()
        await model.load(from: services, now: now)
        #expect(model.draft.source == .suitcase("s-jose"))
        #expect(model.draft.occasion == .brunch)
    }

    @Test func aSourceAskedForWins() async {
        // "Style me from this suitcase".
        let model = StyleMeModel(source: .suitcase("s-weekend"))
        await model.load(from: services(source: .suitcase), now: now)
        #expect(model.draft.source == .suitcase("s-weekend"))
    }

    @Test func choicesAreRememberedAndTheSuitcaseCountsAsUsed() async throws {
        let services = services()
        let model = StyleMeModel()
        await model.load(from: services, now: now)
        model.choose(source: .suitcase("s-beach"))
        model.update { $0.occasion = .dateNight }
        await model.remember(in: services, now: now)
        let remembered = try await services.profile.profile().remembered
        #expect(remembered == RememberedChoices(source: .suitcase("s-beach"), occasion: .dateNight))
        #expect(try await services.suitcases.suitcase("s-beach").lastUsedAt == now)
        // Other's words are for one request, so Other isn't remembered.
        model.update { $0.occasion = .other }
        await model.remember(in: services, now: now)
        #expect(try await services.profile.profile().remembered.occasion == .dateNight)
    }

    @Test func aMissingSuitcaseIsNotRememberedAndStyleMeAsks() async throws {
        // FR-67: a remembered suitcase that's gone never quietly becomes the main closet.
        let services = services(source: .suitcase)
        try await services.suitcases.delete("s-jose")
        let model = StyleMeModel()
        await model.load(from: services, now: now)
        #expect(model.draft.source == .suitcase("s-jose"))
        #expect(model.check.issues.contains(.suitcaseMissing))
        await model.remember(in: services, now: now)
        #expect(try await services.profile.profile().remembered.source == .suitcase("s-jose"))
        // Home's suitcase shows the main closet meanwhile (PRD §7.7).
        let home = HomeModel()
        await home.load(from: services)
        #expect(home.content.source.kind == .mainCloset)
    }

    @Test func homeShowsTheOccasionOnTheCalendar() async throws {
        let services = services()
        try await services.profile.change { $0.remembered.occasion = .concert }
        let home = HomeModel()
        await home.load(from: services)
        #expect(home.content.occasion == .concert)
        #expect(RoomControl.occasion.accessibilityLabel(for: home.content) == "Calendar: Occasion, Concert")
        #expect(RoomControl.occasion.rowLabel(for: home.content) == "Occasion: Concert")
    }

    @Test func addToASuitcaseFromGarmentDetail() async throws {
        let services = services()
        let model = GarmentDetailModel(garmentID: "g-tan-loafers")
        await model.load(from: services, now: now)
        #expect(model.suitcases.isEmpty)
        #expect(model.activeSuitcases.count == 5)
        #expect(!model.activeSuitcases.contains { $0.isArchived })
        #expect(try await model.toggleSuitcase("s-spring", in: services))
        #expect(model.suitcases.map(\.name) == ["Spring trip"])
        #expect(!(try await model.toggleSuitcase("s-spring", in: services)))
        #expect(model.suitcases.isEmpty)
    }
}
