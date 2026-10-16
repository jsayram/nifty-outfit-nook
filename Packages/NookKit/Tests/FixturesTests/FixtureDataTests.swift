import Foundation
import Models
import NookTestSupport
import Testing

@testable import Fixtures

extension FixtureData: FixtureDataLike {}

/// Checks that hold for every fixture set: unique IDs and no dangling references.
private func expectConsistent(_ data: FixtureData) {
    let garmentIDs = Set(data.garments.map(\.id))
    #expect(garmentIDs.count == data.garments.count, "garment IDs are unique")
    #expect(Set(data.looks.map(\.id)).count == data.looks.count, "look IDs are unique")
    #expect(Set(data.suitcases.map(\.id)).count == data.suitcases.count, "suitcase IDs are unique")
    let suitcaseNames = data.suitcases.map { $0.name.lowercased() }
    #expect(Set(suitcaseNames).count == suitcaseNames.count, "suitcase names are unique")
    for look in data.looks {
        #expect(look.garmentIDs.allSatisfy(garmentIDs.contains), "\(look.id) only uses known garments")
        #expect((2...6).contains(look.pieces.count), "\(look.id) has 2 to 6 pieces")
    }
    for suitcase in data.suitcases {
        #expect(suitcase.garmentIDs.isSubset(of: garmentIDs), "\(suitcase.id) only holds known garments")
    }
    for garment in data.garments {
        #expect((try? NameRules.garmentName(garment.name)) == garment.name, "\(garment.id) has a valid name")
        #expect(garment.wornOn.allSatisfy { $0 >= garment.addedAt }, "\(garment.id) wasn't worn before it was added")
    }
}

struct DemoClosetTests {
    private let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)

    @Test func hasTheTwentyOneDemoGarments() {
        #expect(data.garments.count == 21)
        expectConsistent(data)
    }

    @Test func profileIsLilyWithFreshPreferences() {
        #expect(data.profile.signName == "Lily")
        #expect(data.profile.preferences == Preferences())
    }

    @Test func holdsNoBodyMeasurements() {
        // The repo is public: fixtures carry no body or health details (DATA_MAP.md).
        #expect(data.profile.measurements.isEmpty)
        #expect(data.profile.tryOnPhoto == nil)
    }

    @Test func coversEveryGarmentState() {
        let garments = data.garments
        #expect(garments.contains { $0.ownership == .wishlisted })
        #expect(garments.contains { $0.ownership == .noLongerOwned })
        #expect(garments.contains { $0.ownership == .purchased(.notArrived) })
        #expect(garments.contains { $0.isDeleted })
        #expect(garments.contains { $0.isArchived })
        #expect(garments.contains { $0.laundry == .dirty && $0.isInCloset })
        #expect(garments.contains { if case .unavailable = $0.availability { true } else { false } })
        #expect(garments.contains { $0.photo == .noPhoto })
        #expect(garments.contains { $0.lastWorn != nil })
        #expect(garments.count { $0.isInCloset } == 17)
    }

    @Test func hasMoreSuitcasesThanFavourites() {
        let shelf = SuitcaseShelf(data.suitcases)
        #expect(shelf.favorites.map(\.name) == ["Jose's house", "Weekend", "Gym"])
        #expect(shelf.showsSeeAll)
        #expect(shelf.all.count == 5)
        #expect(shelf.archived.map(\.name) == ["Old dorm"])
        #expect(data.suitcases.contains { $0.garmentIDs.isEmpty })
    }

    @Test func hasSavedLooksOfEveryKind() {
        let looks = data.looks
        #expect(looks.contains { $0.isMadeByHer && $0.isSaved })
        #expect(looks.contains { $0.version == .somethingNew && $0.ideas.count == 1 && $0.isSaved })
        #expect(looks.contains { !$0.isSaved })
        #expect(looks.contains { $0.source.isSuitcase })
        #expect(looks.contains { $0.lastWorn != nil })
    }

    @Test func wornPiecesMatchWornLooks() {
        let garments = Dictionary(uniqueKeysWithValues: data.garments.map { ($0.id, $0) })
        for look in data.looks {
            for worn in look.wornOn {
                for id in look.garmentIDs {
                    #expect(garments[id]?.wornOn.contains(worn) == true, "\(id) worn with \(look.id)")
                }
            }
        }
    }

    @Test func weatherIsFiftyEightAndRain() {
        #expect(data.weather.condition == .rain)
        #expect(Int((data.weather.temperatureCelsius * 9 / 5 + 32).rounded()) == 58)
    }

    @Test func datesFollowNow() {
        let later = FixtureSet.demo.data(now: TestTime.day(10), calendar: TestTime.calendar)
        let interview = later.looks.first { $0.id == "o-interview" }
        #expect(interview?.lastWorn == TestTime.day(5))
    }

    @Test func recordsSurviveEncoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode([Garment].self, from: encoder.encode(data.garments)) == data.garments)
        #expect(try decoder.decode([Look].self, from: encoder.encode(data.looks)) == data.looks)
        #expect(try decoder.decode([Suitcase].self, from: encoder.encode(data.suitcases)) == data.suitcases)
        #expect(try decoder.decode(Profile.self, from: encoder.encode(data.profile)) == data.profile)
    }
}

struct EmptyClosetTests {
    @Test func isAFreshInstall() {
        let data = FixtureSet.empty.data(now: TestTime.now, calendar: TestTime.calendar)
        #expect(data.garments.isEmpty)
        #expect(data.looks.isEmpty)
        #expect(data.suitcases.isEmpty)
        #expect(data.profile == Profile())
    }
}

struct LargeClosetTests {
    private let data = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)

    @Test func hasMoreThanTwoThousandGarments() {
        #expect(data.garments.count >= 2_000)
        #expect(data.garments.count { $0.isInCloset } >= 2_000)
        #expect(data.looks.count >= 500)
        #expect(data.suitcases.count >= 30)
        expectConsistent(data)
    }

    @Test func isTheSameEveryTime() {
        let again = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)
        #expect(again.garments == data.garments)
        #expect(again.looks == data.looks)
        #expect(again.suitcases == data.suitcases)
    }

    @Test func mixesEveryCategoryAndState() {
        #expect(Set(data.garments.map(\.category)) == Set(GarmentCategory.allCases))
        #expect(data.garments.contains { $0.ownership == .wishlisted })
        #expect(data.garments.contains { $0.isDeleted })
        #expect(data.garments.contains { $0.laundry == .dirty })
        #expect(data.suitcases.contains { $0.isArchived })
    }

    @Test func generatorIsStable() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        #expect((0..<100).map { _ in first.next() } == (0..<100).map { _ in second.next() })
        var bounded = SeededGenerator(seed: 7)
        #expect((0..<1_000).allSatisfy { _ in (3...9).contains(bounded.int(in: 3...9)) })
    }
}
