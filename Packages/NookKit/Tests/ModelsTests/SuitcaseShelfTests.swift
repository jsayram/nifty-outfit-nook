import Foundation
import Models
import NookTestSupport
import Testing

struct SuitcaseShelfTests {
    private func suitcase(_ id: Suitcase.ID, usedDaysAgo: Int?, archived: Bool = false) -> Suitcase {
        Suitcase(
            id: id,
            name: "Case \(id)",
            lastUsedAt: usedDaysAgo.map { TestTime.day(-$0) },
            isArchived: archived,
            createdAt: TestTime.day(-100)
        )
    }

    @Test(arguments: [(0, 0, false), (1, 1, false), (2, 2, false), (3, 3, false), (5, 3, true)])
    func showsUpToThreeFavouritesAndSeeAllAboveThree(count: Int, favorites: Int, seeAll: Bool) {
        // RD-09.1
        let suitcases = (0..<count).map { suitcase(Suitcase.ID("s-\($0)"), usedDaysAgo: $0) }
        let shelf = SuitcaseShelf(suitcases)
        #expect(shelf.favorites.count == favorites)
        #expect(shelf.showsSeeAll == seeAll)
        #expect(shelf.all.count == count)
    }

    @Test func favouritesAreTheMostRecentlyUsed() {
        let shelf = SuitcaseShelf([
            suitcase("s-old", usedDaysAgo: 50),
            suitcase("s-never", usedDaysAgo: nil),
            suitcase("s-new", usedDaysAgo: 1),
            suitcase("s-mid", usedDaysAgo: 10),
        ])
        #expect(shelf.favorites.map(\.id) == ["s-new", "s-mid", "s-old"])
        #expect(shelf.all.map(\.id) == ["s-new", "s-mid", "s-old", "s-never"])
    }

    @Test func usingASuitcaseMakesItAFavourite() {
        // RD-09.2: markUsed sets lastUsedAt; the shelf does the rest.
        var suitcases = [
            suitcase("s-1", usedDaysAgo: 1),
            suitcase("s-2", usedDaysAgo: 2),
            suitcase("s-3", usedDaysAgo: 3),
            suitcase("s-4", usedDaysAgo: nil),
        ]
        #expect(!SuitcaseShelf(suitcases).favorites.map(\.id).contains("s-4"))
        suitcases[3].lastUsedAt = TestTime.now
        #expect(SuitcaseShelf(suitcases).favorites.map(\.id) == ["s-4", "s-1", "s-2"])
    }

    @Test func archivedSuitcasesOnlyShowUnderTheirFilter() {
        // RD-09.3
        let shelf = SuitcaseShelf([suitcase("s-1", usedDaysAgo: 1, archived: true), suitcase("s-2", usedDaysAgo: 5)])
        #expect(shelf.favorites.map(\.id) == ["s-2"])
        #expect(shelf.all.map(\.id) == ["s-2"])
        #expect(shelf.archived.map(\.id) == ["s-1"])
    }

    @Test func neverUsedSuitcasesSortNewestFirstThenByName() {
        let older = Suitcase(id: "s-a", name: "Beach", createdAt: TestTime.day(-9))
        let newer = Suitcase(id: "s-b", name: "Zoo", createdAt: TestTime.day(-1))
        let sameDay = Suitcase(id: "s-c", name: "alps", createdAt: TestTime.day(-9))
        #expect(SuitcaseShelf([older, sameDay, newer]).all.map(\.id) == ["s-b", "s-c", "s-a"])
    }
}
